require "../types"

module Crystal
  # This class generates stable type IDs based on the fully qualified name of types.
  # Unlike LLVMId, these IDs are consistent across different compilation units,
  # making them suitable for shared libraries.
  class StableTypeId
    # FNV-1a hash parameters
    private FNV_PRIME   =   16777619_u32
    private FNV_OFFSET  = 2166136261_u32
    private MAX_TYPE_ID =     2147483647 # Int32::MAX

    # Computes a stable hash for a type based on its fully qualified name
    def self.hash_type(type : Type) : Int32
      # For nil type, always return 0 (same as in LLVMId)
      return 0 if type.is_a?(NilType)

      # Get the fully qualified name of the type
      full_name = get_full_type_name(type)

      # Compute FNV-1a hash of the type name
      hash = compute_fnv1a_hash(full_name)

      # Ensure the hash is within Int32 range and not negative
      (hash % MAX_TYPE_ID).to_i32
    end

    # Gets the fully qualified name of a type, including generic parameters if applicable
    private def self.get_full_type_name(type : Type) : String
      case type
      when GenericClassInstanceType
        # Include generic type parameters in the name
        generic_args = type.type_vars.values.map do |type_var|
          case type_var
          when Var
            get_full_type_name(type_var.type)
          when NumberLiteral
            type_var.value
          else
            type_var.to_s
          end
        end
        "#{type.generic_type}(#{generic_args.join(",")})"
      when TypeDefType
        # Use the underlying type for typedefs
        get_full_type_name(type.typedef)
      when VirtualType, VirtualMetaclassType
        # Use the base type for virtual types
        get_full_type_name(type.base_type)
      else
        # For other types, use their string representation
        type.to_s
      end
    end

    # Computes FNV-1a hash of a string
    private def self.compute_fnv1a_hash(str : String) : UInt32
      hash = FNV_OFFSET
      str.each_byte do |byte|
        hash = hash ^ byte
        hash = hash &* FNV_PRIME
      end
      hash
    end
  end
end
