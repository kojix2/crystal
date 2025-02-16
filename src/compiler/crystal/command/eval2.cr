require "colorize"

class Crystal::Command
  # This overwrites the `crystal eval` command
  private def eval
    compiler = new_compiler
    opt_program_source = nil

    loop_mode = false
    print_mode = false
    auto_split = true

    separator = nil

    library_name = [] of String
    before_code = [] of String
    after_code = [] of String

    dir_path = Dir.current

    debug_mode = false

    program_args = [] of String

    parse_with_crystal_opts do |opts|
      opts.banner = "Usage: crystal eval [options] [source]\n\nOptions:"
      setup_simple_compiler_options compiler, opts

      opts.separator ""
      opts.on("-r LIBRARY", "Require the library") { |name| library_name << name }
      opts.on("-N", "Loop over each line of input") { loop_mode = true }
      opts.on("-P", "Same as -n, but also print result") { loop_mode = true; print_mode = true }
      opts.on("-S SEP", "Set delimiter SEP") { |sep| separator = sep }
      opts.on("-B CODE", "Code to run before the loop") { |code| before_code << code }
      opts.on("--before-file FILE", "File to run before the loop") { |file|
        before_code << File.read(file)
      }
      opts.on("-A CODE", "Code to run after the loop") { |code| after_code << code }
      opts.on("--after-file FILE", "File to run after the loop") { |file|
        after_code << File.read(file)
      }
      opts.on("-C DIR", "--chdir DIR", "Change to directory DIR before executing") { |dir| dir_path = dir }
      opts.on("--debug-program", "Print the generated program") { debug_mode = true }

      opts.unknown_args do |before_dash, after_dash|
        opt_program_source = before_dash.join "\n"
        program_args = after_dash
      end
    end

    program_source = opt_program_source
    if program_source.nil?
      program_source = STDIN.gets_to_end
    end

    unless library_name.empty?
      program_source = String.build do |str|
        library_name.each do |name|
          str << "require \"#{name}\"\n"
        end
        str << program_source
      end
    end

    if loop_mode
      program_source = String.build do |str|
        before_code.each { |code| str << code << "\n" }
        str << "while l = gets\n"
        if separator
          str << "  f = l.chomp.split(\"#{separator}\")\n"
        else
          # I hope that if the variable `f` is not used, the `split` process
          # is completely eliminated by the LLVM optimization process,
          # but I have not checked to see if this is really the case.
          str << "  f = l.chomp.split\n"
        end
        str << "  r = (\n"
        str << "    l\n"
        str << "    #{program_source}\n"
        str << "  )\n"
        str << "puts r unless r.nil?\n" if print_mode
        str << "end\n"
        after_code.each { |code| str << code << "\n" }
      end
    end

    if debug_mode
      puts "# Generated Code:\n#{program_source.colorize(:green)}"
      puts "# Program Args: #{program_args.inspect.colorize(:green)}"
      return
    end

    sources = [Compiler::Source.new("eval", program_source)]
    output_filename = Crystal.temp_executable "eval"

    compiler.compile sources, output_filename
    Dir.cd(dir_path) do
      execute output_filename, program_args, compiler
    end
  end
end
