class Crystal::Command
  # This overwrites the `crystal eval` command
  private def eval
    compiler = new_compiler

    loop_mode = false
    print_mode = false
    auto_split = true

    before_loop = nil
    after_loop = nil

    dir_path = Dir.current

    debug_mode = false

    program_args = [] of String
    if double_dash_index = options.index("--")
      program_args = options[double_dash_index + 1..-1]
      options.truncate(0, double_dash_index)
    end

    parse_with_crystal_opts do |opts|
      opts.banner = "Usage: crystal eval [options] [source]\n\nOptions:"
      setup_simple_compiler_options compiler, opts

      opts.separator ""
      opts.on("-N", "Loop over each line of input") { loop_mode = true }
      opts.on("-P", "Same as -n, but also print result") { loop_mode = true; print_mode = true }
      opts.on("-F", "Do not split each line into fields") { loop_mode = true; auto_split = false }
      opts.on("-B CODE", "Code to run before the loop") { |code| before_loop = code }
      opts.on("--before-file FILE", "File to run before the loop") { |file|
        before_loop = File.read(file)
      }
      opts.on("-A CODE", "Code to run after the loop") { |code| after_loop = code }
      opts.on("--after-file FILE", "File to run after the loop") { |file|
        after_loop = File.read(file)
      }
      opts.on("-C DIR", "--chdir DIR", "Change to directory DIR before executing") { |dir| dir_path = dir }
      opts.on("--debug-program", "Print the generated program") { debug_mode = true }
    end

    program_source = options.join "\n"

    if loop_mode
      wrapped_code = String.build do |str|
        str << before_loop << "\n" if before_loop
        str << "while l = gets\n"
        str << "  f = l.chomp.split\n" if auto_split
        str << "  r = (\n"
        str << "    _l\n"
        str << "    #{program_source}\n"
        str << "  )\n"
        str << "puts r unless r.nil?\n" if print_mode
        str << "end\n"
        str << after_loop << "\n" if after_loop
      end
      program_source = wrapped_code
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
