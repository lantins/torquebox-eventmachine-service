# --- external dependencies --------------------------------------------------
require 'socket'
require 'eventmachine'
require 'optparse'
require 'fileutils'
require 'yaml'
require 'servolux'
require 'logger'
require 'syslogger' unless /mswin|mingw32|java/ === RUBY_PLATFORM

# --- initial requires -------------------------------------------------------
require 'lividpenguin/version'
require 'lividpenguin/command_line'

# --- setup main module ------------------------------------------------------

module LividPenguin
  class Error < StandardError; end

  # Main method to get everything running.
  def self.run!(argv)
    LividPenguin::CommandLine::run!(argv)
  end
end

# --- server code ------------------------------------------------------------

require 'lividpenguin/connection'
require 'lividpenguin/server'
