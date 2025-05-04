# :nodoc:
module Crystal::System
  # Class variable to store program flags
  @@program_flags : Array(String)?

  # Returns the compiler flags that were used to compile the program
  def self.program_flags : Array(String)
    @@program_flags ||= begin
      flags = [] of String
      # Flags are defined at compile time by the PROGRAM_FLAGS constant
      {% for flag in PROGRAM_FLAGS %}
        flags << {{ flag }}
      {% end %}
      flags
    end
  end
end

# Define a macro that will be expanded at compile time to include all flags
# passed to the compiler
{% begin %}
  {% flags = [] of StringLiteral %}
  {% if flag?(:release) %}
    {% flags << "release" %}
  {% end %}
  {% if flag?(:debug) %}
    {% flags << "debug" %}
  {% end %}
  {% if flag?(:static) %}
    {% flags << "static" %}
  {% end %}
  {% if flag?(:shared_library_support) %}
    {% flags << "shared_library_support" %}
  {% end %}
  
  # Add any other flags from the compiler
  # Note: We can add more compiler flags here if needed
  
  # Define the constant with all flags
  PROGRAM_FLAGS = {{ flags }}
{% end %}
