require "../syntax/ast"
require "../syntax/visitor"

module Crystal
  # Visitor that collects all method calls and method definitions
  # before semantic analysis to detect undefined method calls
  # that would otherwise be hidden by NoReturn type pruning
  class UndefinedMethodChecker < Visitor
    # All method calls found during AST traversal
    getter undefined_calls = [] of {Call, Location}

    # All method definitions found during AST traversal
    getter defined_methods = Set(String).new

    # Class and module method definitions (self.method_name)
    getter defined_class_methods = Set(String).new

    # Track current scope for better method resolution
    @current_scope : String = ""
    @scope_stack = [] of String

    def visit(node : Call)
      # Record all method calls with their locations
      if location = node.location
        @undefined_calls << {node, location}
      end
      true
    end

    def visit(node : Def)
      # Record method definitions
      method_name = node.name

      if node.receiver
        # Class method (def self.method_name or def Type.method_name)
        @defined_class_methods << method_name
      else
        # Instance method - include scope information for better resolution
        if @current_scope.empty?
          @defined_methods << method_name
        else
          @defined_methods << method_name
          @defined_methods << "#{@current_scope}##{method_name}"
        end
      end

      true
    end

    def visit(node : ClassDef)
      # Track class scope for better method resolution
      @scope_stack << @current_scope
      @current_scope = node.name.names.join("::")
      true
    end

    def visit(node : ModuleDef)
      # Track module scope for better method resolution
      @scope_stack << @current_scope
      @current_scope = node.name.names.join("::")
      true
    end

    def end_visit(node : ClassDef | ModuleDef)
      # Restore previous scope
      @current_scope = @scope_stack.pop
    end

    def visit(node : LibDef)
      # Skip lib definitions as they have different method resolution rules
      false
    end

    def visit(node : Macro)
      # Record macro definitions as they can be called like methods
      @defined_methods << node.name
      true
    end

    def visit(node : ASTNode)
      # Default visitor for all other AST nodes
      true
    end

    # Process the AST and return undefined method calls
    def process(ast_node : ASTNode) : Array({Call, Location})
      # First pass: collect all calls and definitions
      ast_node.accept(self)

      # Second pass: identify truly undefined calls
      undefined = [] of {Call, Location}

      @undefined_calls.each do |call, location|
        method_name = call.name

        # Skip certain built-in methods and operators
        next if builtin_method?(method_name)

        # Check if method is defined
        is_defined = @defined_methods.includes?(method_name) ||
                     @defined_class_methods.includes?(method_name) ||
                     stdlib_method?(method_name)

        unless is_defined
          undefined << {call, location}
        end
      end

      undefined
    end

    # Check if a method is a built-in method or operator
    private def builtin_method?(name : String) : Bool
      # Common operators and built-in methods that don't need explicit definition
      builtin_methods = {
        "+", "-", "*", "/", "%", "**",
        "==", "!=", "<", ">", "<=", ">=", "<=>",
        "&&", "||", "!",
        "[]", "[]=", "<<", ">>",
        "&", "|", "^", "~",
        "not_nil!", "nil?", "is_a?", "as", "as?",
        "responds_to?", "class", "typeof",
        "puts", "print", "p", "pp",
        "raise", "exit", "abort",
        "new", "initialize", "finalize",
        "to_s", "inspect", "hash", "dup", "clone",
      }

      builtin_methods.includes?(name)
    end

    # Check if a method is likely from the standard library
    # This is a simplified check - in a full implementation,
    # we would need more sophisticated stdlib method detection
    private def stdlib_method?(name : String) : Bool
      # Common stdlib methods that are always available
      stdlib_methods = {
        "size", "length", "empty?", "first", "last",
        "each", "map", "select", "reject", "find",
        "include?", "index", "rindex", "join",
        "split", "strip", "chomp", "upcase", "downcase",
        "to_i", "to_f", "to_s", "to_a", "to_h",
        "keys", "values", "has_key?", "fetch",
        "push", "pop", "shift", "unshift", "clear",
        "sort", "reverse", "flatten", "compact",
        "min", "max", "sum", "count", "any?", "all?",
        "times", "upto", "downto", "step",
      }

      stdlib_methods.includes?(name)
    end
  end
end
