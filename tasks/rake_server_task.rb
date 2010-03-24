desc "Rake Server"
namespace :rakeserver do
  desc "Start the Rake Server"
  task :start do
    require 'rake-server'
    server = RakeServer::Server.new
    server.startup
  end
end
