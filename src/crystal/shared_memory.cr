require "lib_c"

# Define only what's not already in lib_c
{% if flag?(:unix) %}
  lib LibC
    fun shm_open(name : LibC::Char*, oflag : Int32, mode : LibC::ModeT) : Int32
    fun shm_unlink(name : LibC::Char*) : Int32
  end
{% elsif flag?(:win32) %}
  lib LibC
    # Windows API functions for shared memory
    fun CreateFileMappingA(hFile : Void*, lpFileMappingAttributes : Void*, flProtect : UInt32, dwMaximumSizeHigh : UInt32, dwMaximumSizeLow : UInt32, lpName : LibC::Char*) : Void*
    fun OpenFileMappingA(dwDesiredAccess : UInt32, bInheritHandle : Int32, lpName : LibC::Char*) : Void*
    fun MapViewOfFile(hFileMappingObject : Void*, dwDesiredAccess : UInt32, dwFileOffsetHigh : UInt32, dwFileOffsetLow : UInt32, dwNumberOfBytesToMap : UInt64) : Void*
    fun UnmapViewOfFile(lpBaseAddress : Void*) : Int32
    fun CloseHandle(hObject : Void*) : Int32
  end
{% end %}

module Crystal
  # :nodoc:
  # This module provides a cross-platform way to create and manage shared memory
  # between processes and shared libraries.
  module SharedMemory
    {% if flag?(:unix) %}
      # Constants for shm_open flags
      O_RDONLY = 0x0000
      O_RDWR   = 0x0002
      O_CREAT  = 0x0200
      O_EXCL   = 0x0800
      O_TRUNC  = 0x0400

      # Constants for mmap protection
      PROT_READ  = 0x1
      PROT_WRITE = 0x2

      # Constants for mmap flags
      MAP_SHARED = 0x01
      MAP_FAILED = Pointer(Void).new(UInt64::MAX) # -1 as UInt64

      # Creates or opens a shared memory region with the given name and size
      def self.create(name : String, size : Int32) : Pointer(Void)
        # Create a unique name for the shared memory region
        shm_name = "/crystal_#{name}_#{Process.pid}"

        # Open the shared memory object
        fd = LibC.shm_open(shm_name.to_unsafe, O_RDWR | O_CREAT, 0o666)
        if fd < 0
          raise RuntimeError.new("Failed to create shared memory: #{Errno.value}")
        end

        # Set the size of the shared memory object
        if LibC.ftruncate(fd, size) < 0
          LibC.close(fd)
          LibC.shm_unlink(shm_name)
          raise RuntimeError.new("Failed to set shared memory size: #{Errno.value}")
        end

        # Map the shared memory object into the process's address space
        ptr = LibC.mmap(nil, size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0)
        if ptr == MAP_FAILED
          LibC.close(fd)
          LibC.shm_unlink(shm_name)
          raise RuntimeError.new("Failed to map shared memory: #{Errno.value}")
        end

        # Close the file descriptor (the mapping remains valid)
        LibC.close(fd)

        # Return the pointer to the shared memory region
        ptr
      end

      # Opens an existing shared memory region with the given name
      def self.open(name : String, size : Int32) : Pointer(Void)?
        # Try to open existing shared memory regions with different PIDs
        Dir.glob("/dev/shm/crystal_#{name}_*") do |path|
          # Extract the basename without the /dev/shm prefix
          basename = File.basename(path)
          shm_name = "/#{basename}"

          # Open the shared memory object
          fd = LibC.shm_open(shm_name.to_unsafe, O_RDWR, 0o666)
          next if fd < 0

          # Map the shared memory object into the process's address space
          ptr = LibC.mmap(nil, size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0)
          LibC.close(fd)

          return ptr unless ptr == MAP_FAILED
        end

        nil
      end

      # Unmaps and unlinks a shared memory region
      def self.destroy(ptr : Pointer(Void), name : String, size : Int32) : Nil
        # Unmap the shared memory region
        LibC.munmap(ptr, size)

        # Unlink the shared memory object
        shm_name = "/crystal_#{name}_#{Process.pid}"
        LibC.shm_unlink(shm_name.to_unsafe)
      end
    {% elsif flag?(:win32) %}
      # Windows implementation using CreateFileMapping and MapViewOfFile
      # Use existing Windows API bindings

      # Constants for CreateFileMapping
      PAGE_READWRITE       = 0x04
      INVALID_HANDLE_VALUE = Pointer(Void).new(UInt64::MAX) # -1 as UInt64

      # Constants for OpenFileMapping
      FILE_MAP_ALL_ACCESS = 0xF001F

      # Creates or opens a shared memory region with the given name and size
      def self.create(name : String, size : Int32) : Pointer(Void)
        # Create a unique name for the shared memory region
        shm_name = "Crystal_#{name}_#{Process.pid}"

        # Create a file mapping object
        handle = LibC.CreateFileMappingA(INVALID_HANDLE_VALUE, nil, PAGE_READWRITE, 0, size, shm_name.to_unsafe)
        if handle.null?
          raise RuntimeError.new("Failed to create shared memory")
        end

        # Map the file mapping object into the process's address space
        ptr = LibC.MapViewOfFile(handle, FILE_MAP_ALL_ACCESS, 0, 0, size)
        if ptr.null?
          LibC.CloseHandle(handle)
          raise RuntimeError.new("Failed to map shared memory")
        end

        # Return the pointer to the shared memory region
        ptr
      end

      # Opens an existing shared memory region with the given name
      def self.open(name : String, size : Int32) : Pointer(Void)?
        # Try to open existing shared memory regions
        # This is a simplified approach - in a real implementation,
        # we would need a way to discover existing mappings
        search_pattern = "Crystal_#{name}_*"
        handle = LibC.OpenFileMappingA(FILE_MAP_ALL_ACCESS, 0, search_pattern.to_unsafe)
        return nil if handle.null?

        ptr = LibC.MapViewOfFile(handle, FILE_MAP_ALL_ACCESS, 0, 0, size)
        LibC.CloseHandle(handle)

        ptr.null? ? nil : ptr
      end

      # Unmaps and closes a shared memory region
      def self.destroy(ptr : Pointer(Void), name : String, size : Int32) : Nil
        # Unmap the view of the file
        LibC.UnmapViewOfFile(ptr)

        # The handle is closed when the process terminates
      end
    {% else %}
      # Fallback implementation for unsupported platforms
      def self.create(name : String, size : Int32) : Pointer(Void)
        raise RuntimeError.new("Shared memory is not supported on this platform")
      end

      def self.open(name : String, size : Int32) : Pointer(Void)?
        nil
      end

      def self.destroy(ptr : Pointer(Void), name : String, size : Int32) : Nil
      end
    {% end %}
  end
end
