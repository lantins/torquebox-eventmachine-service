module LividPenguin
  # Command Line
  #
  # - Parses command line options.
  # - Loads YAML configuration file (if provided).
  # - Starts server using options in foreground or daemon mode.
  module CommandLine

    # Default configuration options.
    #
    # @return [Hash]
    def self.default_options
      gem_dir = ::File.expand_path(::File.join(::File.dirname(__FILE__), '..', '..'))

      {
        :address => '0.0.0.0',
        :port => 42690,
        :pid_path => gem_dir + '/tmp',
        :log_level => Logger::DEBUG,
        :foreground => false,
      }
    end

    # Run the server.
    # Parses ARGV and starts server in foreground or daemon mode.
    #
    # @param [Array] argv   array of ARGV input
    def self.run!(argv)
      # parse options.
      options = parse_args(argv)
      # run server in foreground if asked.
      options[:foreground] ? run_foreground!(options) : run_daemon!(options)
    end

    # Parses command line flags/options.
    #
    # @param [Array] argv   array of ARGV input
    # @return [Hash] parsed options hash, keys are :symbols
    def self.parse_args(argv)
      # load defaults.
      options = default_options
      # order options are set: default, config, command line.
      parser = setup_option_parser(options)

      # attempt to parse options.
      begin
        # parse em.
        parser.parse!(argv)
      # friendly output when parsing fails
      rescue OptionParser::InvalidOption, OptionParser::MissingArgument => error
        $stdout.puts error.to_s
        abort
      end

      # return parsed options.
      options
    end

    # Run server in foreground mode.
    #
    # @param [Hash] options hash
    def self.run_foreground!(options, logger = create_foreground_logger(options[:log_level]))
      # configure server instance.
      server = LividPenguin::Server.new(options, logger)
      # inform the user how to escape.
      $stdout.puts "\n"
      $stdout.puts "    +++ Running server in foreground."
      $stdout.puts "    +++ Terminate with ^C (Ctrl+C)."
      $stdout.puts "\n"
      # now start it up.
      server.startup(true) # true = wait until server has shutdown completely
    end

    # Run server as background daemon, syslogd is used for logging.
    #
    # @param [Hash] options hash
    def self.run_daemon!(options)
      if /mswin|mingw32/ === RUBY_PLATFORM
        # On Windows we have to effectively run in foreground although we can still log to files
        win_logger = Logger.new('log/server.log')
        win_logger.level = options[:log_level]
        run_foreground!(options, win_logger)
      else
        # Other OS get proper daemon mode with syslogging
        # configure daemon.
        daemon = configure_daemon(options)
        # make sure its not already running.
        exit_if_daemon_is_already_running!(daemon)
        # attempt to start the daemon.
        begin
          daemon.startup(false) # false = prevent parent exiting after daemon start
        rescue => err
          daemon.logger.error "Exception encountered while starting: #{err.message}"
          err.backtrace.each { |line| daemon.logger.error "    backtrace: #{line}" }
          exit(1)
        end
      end
    end

    # Setup options parser, will be used to parse ARGV input.
    #
    # @param [Hash] options hash
    # @return [OptionParser]
    def self.setup_option_parser(options)
      OptionParser.new('', 26, '  ') do |parser|
        parser.banner = 'Usage: lividpenguin-server [options]'
        parser.separator ''
        parser.separator 'Daemon options:'
        parser.on('-h', '--help', 'show this message') { $stderr.puts parser; exit; }
        parser.on('-v', '--version', 'show version number') { $stderr.puts 'Livid Penguin - Server - v' + LividPenguin::Version; exit }
        parser.on('-p', '--pid-path PATH', 'PATH to store PID file') { |path| options[:pid_path] = path }
        parser.on('-f', '--foreground', 'do not fork, run in foreground mode') { options[:foreground] = true }
        parser.on('-l', '--log-level LEVEL', 'logging verbosity level; [debug, info, warn] (default: warn)') { |level| options[:log_level] = string_to_logging_level(level) }
        parser.separator ''
        parser.separator 'Network options:'
        parser.on('-A', '--address HOST', 'listen on specified address (default: 0.0.0.0)') { |host| options[:address] = host }
        parser.on('-P', '--port PORT', 'accept connections on specified port number (default: 42690)') { |port| options[:port] = port }
      end
    end

    # Load configuration options from YAML file and merge options.
    # Command line settings overrides configuration file.
    #
    # YAML keys must be prefixed with `:`, so Ruby sees them as symbols.
    #
    # @param [String] file path/filename.yml to load
    # @param [Hash] options hash
    # @return [Hash] merged options
    def self.load_config_and_merge!(file, options)
      config = YAML.load_file(file)
      # Merge options with config, config wins over defaults.
      options.merge!(config)
    end

    # Configure daemon instance to run our server.
    #
    # @param [Hash] options hash
    # @return [Servolux::Daemon]
    def self.configure_daemon(options)
      # log startup information to STDOUT.
      logger = create_foreground_logger(Logger::DEBUG)
      # log to syslogd in daemon mode.
      syslog_name = "#{LividPenguin::Server::DAEMON_NAME}[#{options[:port]}]"
      syslog = create_syslogd_logger(syslog_name, options[:log_level])
      # configure server & daemon instance.
      server = LividPenguin::Server.new(options, syslog)
      daemon = Servolux::Daemon.new(:server => server)
      # display daemon related stuff in stdout logger.
      daemon.logger = logger
      daemon
    end

    # Exit execution if the daemon is already running (checks PID file).
    #
    # @param [Servolux::Daemon]
    def self.exit_if_daemon_is_already_running!(daemon)
      if daemon.alive?
        daemon.logger.error "Already running; pid: #{daemon.pid_file}"
        exit(1)
      end
    end

    # Convert string into its ruby Logger level equivalent.
    #
    # @param [String] level (debug, info or warn)
    # @return [Object]
    def self.string_to_logging_level(level)
      case level
        when 'debug' then Logger::DEBUG
        when 'info' then Logger::INFO
        when 'warn' then Logger::WARN
        else Logger::INFO
      end
    end

    # Creates a logger for usage in the foreground.
    # @param [String] level (debug, info or warn)
    def self.create_foreground_logger(level)
      logger = Logger.new($stdout)
      logger.formatter = proc do |severity, datetime, progname, msg|
        datetime = datetime.strftime('%Y-%m-%d %H:%M:%S.%3N')
        "#{datetime} | #{severity.downcase.rjust(5)} | #{msg}\n"
      end
      logger.level = level
      logger
    end

    # Creates a syslogd logger; LOG_LOCAL0 is used.
    #
    # @return [Syslogger]
    def self.create_syslogd_logger(name, level)
      new_logger = Syslogger.new(name, Syslog::LOG_PID, Syslog::LOG_LOCAL0)
      # set our minimal logging level.
      new_logger.level = level
      new_logger
    end
  end
end
