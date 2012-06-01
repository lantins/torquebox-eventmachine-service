require 'lividpenguin'

class ServerWrapper
  def initialize(opts = {})
  end

  def start
    logger = TorqueBox::Logger.new('com.lividpenguin.server')
    # configure server instance.
    options = LividPenguin::CommandLine.default_options
    @server = LividPenguin::Server.new(options, logger)
    # now start in new thread.
    Thread.new {
      @server.startup(false) # false = prevent parent exiting after daemon start
    }
  end

  def stop
    @server.int
  end

end
