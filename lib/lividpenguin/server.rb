module LividPenguin
  # Background server daemon based around Event Machine event reactor.
  class Server < Servolux::Server
    # Name of the daemon, used to build PID file name and in procline.
    DAEMON_NAME = 'lividpenguin-server'

    attr_reader :config, :logger

    # Class initializer.
    #
    # @param [Hash] config options
    # @param [Object] logger
    def initialize(config, logger)
      @config, @logger = config, logger

      # call Servolux::Servolux initialize method.
      super(DAEMON_NAME, :pid_file => pid_file, :logger => @logger)
    end

    # Boot our EventMachine reactor loop.
    # If method returns or raises exceptions it will be automatically re-executed.
    def run
      procline 'recovering (starting)'
      log(:info, '-' * 32)
      log(:info, 'recovering...')
      # start EM reactor.
      EM.run {
        # every 60 seconds touch the pid file.
        EM.add_periodic_timer(60) { touch_pid_file }

        # just started, we know nothing of operational state so we should act
        # like were recovering from some kind of failure.
        recover
        recover_complete
      }

    log(:info, 'event reactor has shutdown')

    rescue RuntimeError => err
      log_exception(err, "Unexpected runtime error - #{err.inspect}")
      blocking_sleep
    rescue Exception => err
      # for anything else were not really expecting.
      log_exception(err, "Unexpected exception raised - #{err.inspect}")
      # crash and burn with a non zero exit code.
      abort(err.inspect)
    end

    # Sleep before re-executing the run loop, to prevent thundering-herd problem.
    # We don't want to thrash resouces if there is a problem.
    def blocking_sleep
      time = rand(10) + 10
      # keep a record of this happening.
      procline "exception; sleeping for ~#{time} seconds before restart"
      log(:info, "sleeping for ~#{time} seconds before restart")
      # now sleep zzzzzzzzzzzz
      sleep(time)
    end

    # Start listning for TCP/IP connections.
    def listen_for_connections
      LividPenguin::Connection.reset_conn_count
      @tcp_ip_server = EM.start_server(@config[:address], @config[:port], LividPenguin::Connection, @logger)
      log(:info, "server listening for connections on: #{@config[:address]}:#{@config[:port]}")
    end

    # Assume nothing of operational state, assume recovering from failure.
    def recover
      listen_for_connections
    end

    # Decorative method only, updates procline and logs were complete.
    def recover_complete
      procline 'listening'
      log(:info, 'recover complete')
    end

    # Touch the PID file to update its modified time.
    def touch_pid_file
      FileUtils.touch(pid_file)
    end

    # Path to PID file.
    #
    # @return [String]
    def pid_file
      @pid_file ||= "#{@config[:pid_path]}/#{DAEMON_NAME}.#{@config[:port]}.pid"
    end

    # Sets the process procline ($0).
    #
    # @param [String] message
    def procline(message)
      $0 = "#{DAEMON_NAME}[#{@config[:port]}]: #{message}"
    end

    # Handle SIGINT, i.e. when someone presses Ctrl+C.
    def int
      EM.stop if EM.reactor_running?
      shutdown
    end

    private

    # Log an exception and its backtrace.
    #
    # @param [Exception] err
    # @param [String] message
    def log_exception(err, message)
      log(:info, '-' * 32)
      log(:warn, "EXCEPTION: #{message}")
      err.backtrace.each { |line| log(:warn, "exception backtrace: #{line}") }
      log(:info, '-' * 32)
    end

    # Log a message with a fancy looking format.
    #
    # @param [Symbol] level to log the message as
    # @param [String] message to log
    def log(level, message)
      category = 'server'
      prefix = category.rjust(8) + ' | ---- | '
      logger.send(level, prefix + message)
    end

  end

end
