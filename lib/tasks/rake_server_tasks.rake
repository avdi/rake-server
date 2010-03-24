desc "Rake Server"
namespace :rakeserver do
  desc "Start the Rake Server"
  task :start do
    init
    service.startup
  end

  desc "Stop the Rake Server"
  task :stop do
    init
    service.shutdown
  end

  desc "Restart the Rake Server"
  task :restart => [:stop, :start]

  desc "Print path of the Rake Server command fifo"
  task :fifo do
    init
    puts server.command_pipe_path
  end

  def init
    require 'rake-server'
    require 'fileutils'
    require 'logger'

    ENV['RS_DAEMON']       ||= 'true'
    ENV['RS_LOG']          ||= File.expand_path('rakeserver.log', root)
    ENV['RS_PID']          ||= File.expand_path('rakeserver.pid', root)
    ENV['RS_COMMAND_PIPE'] ||= File.expand_path('rakeserver.fifo', root)
  end

  def root
    File.dirname(Rake.application.rakefile)
  end

  def server
    logger = if ENV['RS_DAEMON'] == true
               ::Logger.new(ENV['RS_LOG'])
             else
               ::Logger.new($stderr.dup)
             end
    RakeServer::Server.new(
      ENV['RS_COMMAND_PIPE'], 
      :logger => logger,
      :pid_file => ENV['RS_PID'])
  end

  def service
    if ENV['RS_DAEMON'] == 'true'
      Servolux::Daemon.new(
        :server   => server,
        :log_file => ENV['RS_LOG'],
        :pid_file => ENV['RS_PID'])
    else
      server
    end
  end
end

