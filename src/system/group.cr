require "crystal/system/group"

# Represents a group of users on the host system.
#
# NOTE: To use Group, you must explicitly import it with `require "system/group"`
#
# Groups can be retrieved by either group name or their group ID:
#
# ```
# require "system/group"
#
# System::Group.find_by name: "staff"
# System::Group.find_by id: "0"
# ```
class System::Group
  # Raised on group lookup failure.
  class NotFoundError < Exception
  end

  include Crystal::System::Group

  # The group's name.
  def name : String
    system_name
  end

  # The group's identifier.
  def id : String
    system_id
  end

  def_equals_and_hash id

  # Returns the group associated with the given name.
  #
  # Raises `NotFoundError` if no such group exists.
  def self.find_by(*, name : String) : System::Group
    find_by?(name: name) || raise NotFoundError.new("No such group: #{name}")
  end

  # Returns the group associated with the given name.
  #
  # Returns `nil` if no such group exists.
  def self.find_by?(*, name : String) : System::Group?
    Crystal::System::Group.from_name?(name)
  end

  # Returns the group associated with the given ID.
  #
  # Raises `NotFoundError` if no such group exists.
  def self.find_by(*, id : String) : System::Group
    find_by?(id: id) || raise NotFoundError.new("No such group: #{id}")
  end

  # Returns the group associated with the given ID.
  #
  # Returns `nil` if no such group exists.
  def self.find_by?(*, id : String) : System::Group?
    Crystal::System::Group.from_id?(id)
  end

  def to_s(io)
    io << name << " (" << id << ')'
  end
end
