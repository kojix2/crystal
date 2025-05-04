# This file defines the `__crystal_once` functions expected by the compiler. It
# is called each time a constant or class variable has to be initialized and is
# its responsibility to verify the initializer is executed only once and to fail
# on recursion.
#
# It also defines the `__crystal_once_init` function for backward compatibility
# with older compiler releases. It is executed only once at the beginning of the
# program and, for the legacy implementation, the result is passed on each call
# to `__crystal_once`.

require "crystal/pointer_linked_list"
require "crystal/spin_lock"
require "crystal/shared_memory"

module Crystal
  # :nodoc:
  module Once
    # Size of the shared memory region for once flags
    SHARED_MEMORY_SIZE = 1024 * 1024 # 1MB should be enough for most applications

    # Shared memory region for once flags
    class_property shared_memory_ptr : Pointer(Void)? = nil
    class_property shared_memory_size = SHARED_MEMORY_SIZE
    class_property use_shared_memory = false

    struct Operation
      include PointerLinkedList::Node

      getter fiber : Fiber
      getter flag : Bool*

      def initialize(@flag : Bool*, @fiber : Fiber)
        @waiting = PointerLinkedList(Fiber::PointerLinkedListNode).new
      end

      def add_waiter(node) : Nil
        @waiting.push(node)
      end

      def resume_all : Nil
        @waiting.each(&.value.enqueue)
      end
    end

    @@spin = uninitialized SpinLock
    @@operations = uninitialized PointerLinkedList(Operation)

    def self.init : Nil
      @@spin = SpinLock.new
      @@operations = PointerLinkedList(Operation).new

      # Initialize shared memory if shared library support is enabled
      if Crystal::System.program_flags.includes?("shared_library_support")
        @@use_shared_memory = true
        initialize_shared_memory
      end
    end

    private def self.initialize_shared_memory : Nil
      # Try to open an existing shared memory region first
      if ptr = SharedMemory.open("once_flags", SHARED_MEMORY_SIZE)
        @@shared_memory_ptr = ptr
        return
      end

      # If no existing region is found, create a new one
      @@shared_memory_ptr = SharedMemory.create("once_flags", SHARED_MEMORY_SIZE)

      # Initialize the shared memory region
      ptr = @@shared_memory_ptr.not_nil!
      # First 4 bytes are used as a counter for the next available flag slot
      ptr.as(Int32*).value = 4 # Start after the counter
    end

    protected def self.exec(flag : Bool*, &)
      if @@use_shared_memory
        exec_shared(flag) { yield }
      else
        exec_local(flag) { yield }
      end
    end

    # Execute once with shared memory for cross-library support
    private def self.exec_shared(flag : Bool*, &)
      # Get a stable identifier for this flag pointer
      flag_id = flag.address.hash % ((SHARED_MEMORY_SIZE // 4) - 1) + 1

      # Get the shared memory pointer
      shared_ptr = @@shared_memory_ptr.not_nil!

      # Get the pointer to the shared flag
      shared_flag_ptr = (shared_ptr + flag_id * 4).as(Int32*)

      # Use a simple lock-based approach for now
      @@spin.lock
      current_value = shared_flag_ptr.value
      if current_value == 0
        shared_flag_ptr.value = 1
        @@spin.unlock
        # We are the first to set the flag, run the initializer
        begin
          yield
        ensure
          # Mark as fully initialized
          shared_flag_ptr.value = 2
        end
      else
        # Another thread or process is initializing or has initialized
        while shared_flag_ptr.value == 1
          # Wait for the initialization to complete
          Fiber.yield
        end
      end

      # Safety check
      return if shared_flag_ptr.value == 2

      System.print_error "BUG: failed to initialize class variable or constant\n"
      LibC._exit(1)
    end

    # Original implementation for local-only execution
    private def self.exec_local(flag : Bool*, &)
      @@spin.lock

      if flag.value
        @@spin.unlock
      elsif operation = processing?(flag)
        check_reentrancy(operation)
        wait_initializer(operation)
      else
        run_initializer(flag) { yield }
      end

      # safety check, and allows to safely call `Intrinsics.unreachable` in
      # `__crystal_once`
      return if flag.value

      System.print_error "BUG: failed to initialize class variable or constant\n"
      LibC._exit(1)
    end

    private def self.processing?(flag)
      @@operations.each do |operation|
        return operation if operation.value.flag == flag
      end
    end

    private def self.check_reentrancy(operation)
      if operation.value.fiber == Fiber.current
        @@spin.unlock
        raise "Recursion while initializing class variables and/or constants"
      end
    end

    private def self.wait_initializer(operation)
      waiting = Fiber::PointerLinkedListNode.new(Fiber.current)
      operation.value.add_waiter(pointerof(waiting))
      @@spin.unlock
      Fiber.suspend
    end

    private def self.run_initializer(flag, &)
      operation = Operation.new(flag, Fiber.current)
      @@operations.push pointerof(operation)
      @@spin.unlock

      yield

      @@spin.lock
      flag.value = true
      @@operations.delete pointerof(operation)
      @@spin.unlock

      operation.resume_all
    end
  end

  # :nodoc:
  #
  # Never inlined to avoid bloating the call site with the slow-path that should
  # usually not be taken.
  @[NoInline]
  def self.once(flag : Bool*, initializer : Void*)
    Once.exec(flag, &Proc(Nil).new(initializer, Pointer(Void).null))
  end

  # :nodoc:
  #
  # NOTE: should also never be inlined, but that would capture the block, which
  # would be a breaking change when we use this method to protect class getter
  # and class property macros with lazy initialization (the block may return or
  # break).
  #
  # TODO: consider a compile time flag to enable/disable the capture? returning
  # from the block is unexpected behavior: the returned value won't be saved in
  # the class variable.
  def self.once(flag : Bool*, &)
    Once.exec(flag) { yield } unless flag.value
  end
end

{% if compare_versions(Crystal::VERSION, "1.16.0-dev") >= 0 %}
  # :nodoc:
  #
  # We always inline this accessor to optimize for the fast-path (already
  # initialized).
  @[AlwaysInline]
  fun __crystal_once(flag : Bool*, initializer : Void*)
    return if flag.value
    Crystal.once(flag, initializer)

    # tells LLVM to assume that the flag is true, this avoids repeated access to
    # the same constant or class variable to check the flag and try to run the
    # initializer (only the first access will)
    Intrinsics.unreachable unless flag.value
  end
{% else %}
  # :nodoc:
  #
  # Unused. Kept for backward compatibility with older compilers.
  fun __crystal_once_init : Void*
    Pointer(Void).null
  end

  # :nodoc:
  @[AlwaysInline]
  fun __crystal_once(state : Void*, flag : Bool*, initializer : Void*)
    return if flag.value
    Crystal.once(flag, initializer)
    Intrinsics.unreachable unless flag.value
  end
{% end %}
