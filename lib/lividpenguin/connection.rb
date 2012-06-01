module LividPenguin

  # Handles a single socket session to the server.
  class Connection < EM::Connection
    attr_accessor :logger, :conn_count

    @@conn_count = 0

    def self.reset_conn_count
      @@conn_count = 0
    end

    # Class initializer method.
    #
    # @param [Object] logger
    def initialize(logger)
      # we must be passed a logger.
      @logger = logger
      # connection count.
      @conn_count = @@conn_count += 1
      # set instance variable defaults.
      @port = @ip_address = nil
    end

    # New socket created/connection established.
    def post_init
      get_ip_address_and_port_or_close_connection
    end

    # Receive socket data.
    #
    # @param [String] data binary
    def receive_data(data)
      # N.B. THIS IS WHERE THE ODD THINGS GO WRONG, AS DISCUSSED IN IRC...
      log(:warn, :rx, data.chomp)
    end

    # Connection closed, call back method fired by EM.
    # Perform any cleanup required before tossing the connection object.
    def unbind
      log(:info, :socket, 'disconnected')
    end

    # Close the connection and keep track of the fact were closing it.
    def close_connection(*args)
      log(:debug, :socket, 'server closing connection...')
      @intentionally_closed_connection = true
      super(*args)
    end

    # External callback hook; called when another connection from the same
    # client/app has been opened, this connection is now stale and should
    # be closed.
    def connection_stale!
      log(:debug, :socket, 'connection is stale.')
      close_connection
    end

    private

    # Get the ip address and port of the connection, or close it.
    def get_ip_address_and_port_or_close_connection
      peername = get_peername
      if peername.nil?
        log(:error, :socket, 'new socket created, but unable to fetch ip & port, closing connection...')
        close_connection
      else
        @port, @ip_address = Socket::unpack_sockaddr_in(peername)
        log(:debug, :socket, "new socket created (#{@ip_address}:#{@port})")
      end
    end

    # --- Logging Helper Methods -------------------------------------------

    # Main logging method.
    #
    # @param [Symbol] level to log the message as
    # @param [Symbol] category message belongs to
    # @param [String] message to log
    def log(level, category, message)
      log_with_prefix(level, category, (('-' * 5) + '---' + '-' * 25) + ' | ' + message)
    end

    # Underlying log method used by everything else.
    #
    # @param [Symbol] level to log the message as
    # @param [Symbol] category message belongs to
    # @param [String] message to log
    def log_with_prefix(level, category, message)
      logger.send(level, category_prefix(category) + connection_count_prefix + message)
    end

    # Format the `log category` prefix/funky ascii for log messages.
    #
    # @param [Symbol] category message belongs to
    # @return [String]
    def category_prefix(category)
      symbols = case category
        when :rx then '--->'
        when :tx then '<---'
        else '----'
      end
      category.to_s.rjust(8) + " | #{symbols} | "
    end

    # Format the `connection count` prefix for log messages.
    #
    # @return [String]
    def connection_count_prefix
      @conn_count.to_s.rjust(10, ' ') + ' | '
    end

  end
end
