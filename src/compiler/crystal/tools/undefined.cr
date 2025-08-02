require "../syntax/ast"
require "../compiler"
require "./undefined_method_checker"
require "json"
require "csv"

module Crystal
  class Command
    private def undefined
      config, result = compile_no_codegen "tool undefined", path_filter: true, allowed_formats: %w[text json csv]

      # Check for undefined methods
      undefined_checker = UndefinedMethodChecker.new
      undefined_calls = undefined_checker.process(result.node)

      # Filter undefined calls by path includes/excludes
      filtered_undefined = undefined_calls.select do |call, location|
        if filename = location.filename.as?(String)
          paths = ::Path[filename].parents << ::Path[filename]
          includes = config.includes.map { |path| ::Path[path].expand.to_posix.to_s }
          excludes = CrystalPath.default_paths.map { |path| ::Path[path].expand.to_posix.to_s }
          excludes.concat config.excludes.map { |path| ::Path[path].expand.to_posix.to_s }

          match_includes = includes.empty? || includes.any? { |pattern| paths.any? { |path| path == pattern || File.match?(pattern, path.to_posix) } }
          match_excludes = excludes.any? { |pattern| paths.any? { |path| path == pattern || File.match?(pattern, path.to_posix) } }

          match_includes && !match_excludes
        else
          false
        end
      end

      # Sort undefined calls by location
      filtered_undefined.sort_by! do |call, location|
        {
          location.filename.as(String),
          location.line_number,
          location.column_number,
        }
      end

      # Present results using the UndefinedPresenter
      UndefinedPresenter.new(filtered_undefined, format: config.output_format, verbose: config.verbose).to_s(STDOUT)

      # Exit with error if undefined methods found and check mode is enabled
      if config.check && !filtered_undefined.empty?
        exit 1
      end
    end
  end

  record UndefinedPresenter, undefined_calls : Array({Call, Location}), format : String?, verbose : Bool do
    include JSON::Serializable

    def to_s(io)
      case format
      when "json"
        JSON.build(io) { |builder| to_json(builder) }
      when "csv"
        to_csv(io)
      else
        to_text(io)
      end
    end

    def each(&)
      current_dir = Dir.current
      undefined_calls.each do |call, location|
        filename = ::Path[location.filename.as(String)].relative_to(current_dir).to_s
        relative_location = Location.new(filename, location.line_number, location.column_number)
        yield call, relative_location
      end
    end

    def to_text(io)
      if undefined_calls.empty?
        io.puts "No undefined method calls found." if verbose
        return
      end

      io.puts "UNDEFINED METHOD CALLS:" if verbose
      each do |call, location|
        io << location << "\t"
        io << call.name << "\t"
        io << "1 lines"
        io.puts
      end
    end

    def to_json(builder : JSON::Builder)
      builder.array do
        each do |call, location|
          builder.object do
            builder.field "method", call.name
            builder.field "location", location.to_s
            builder.field "file", location.filename.to_s
            builder.field "line", location.line_number
            builder.field "column", location.column_number
          end
        end
      end
    end

    def to_csv(io)
      CSV.build(io) do |builder|
        builder.row do |row|
          row.concat %w[method file line column location]
        end

        each do |call, location|
          builder.row do |row|
            row << call.name
            row << location.filename.to_s
            row << location.line_number
            row << location.column_number
            row << location.to_s
          end
        end
      end
    end
  end
end
