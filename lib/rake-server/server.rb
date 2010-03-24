require 'rubygems'
require 'logger'
require 'servolux'
require 'rake'
require 'pathname'
require 'redirectable-io'
require 'fileutils'

class RakeServer::Server < Servolux::Server
  include RedirectableIO

  attr_reader :command_pipe_path

  def initialize(
      command_pipe_path="rakeserver.fifo", 
      options = {})
    defaults = { 
      :logger   => ::Logger.new($stderr.dup), 
      :interval => 0
    }
    super("rakeserver", defaults.merge(options))
    @command_pipe_path = command_pipe_path
    @root_dir = File.expand_path(File.dirname(Rake.application.rakefile))
  end

  def before_starting
    logger.info "Rake Server is starting up"
    if File.exist?(@command_pipe_path) || system("mkfifo", @command_pipe_path)
      @command_stream = open(@command_pipe_path, 'r+')
    else
      raise "Error #{$?} making pipe '#{@command_pipe_path}'"
    end
  end

  def after_starting
    logger.info "Rake Server is now accepting commands on #{@command_pipe_path}"
  end

  def before_stopping
    logger.info "Rake Server is shutting down"
  end

  def after_stopping
    @command_stream.close
    FileUtils.rm_f(@command_pipe_path)
    logger.info "Rake Server has shut down"
  end

  def run
    Dir.chdir(@root_dir) do
      reenable_tasks!
      
      command = @command_stream.readpartial(1024)
      args    = command.split
      logger.info "Rake Server executing command: '#{command}'"
      tasks, variables = collect_tasks_and_variables(args)
      stdin   = variables.fetch("RS_STDIN")  { $stdin }
      stdout  = variables.fetch("RS_STDOUT") { $stdout }
      stderr  = variables.fetch("RS_STDERR") { $stderr }
      status  = variables.fetch("RS_STATUS") { "/dev/null" }
      client_pid = variables.fetch("RS_CLIENT_PID", nil) 
      with_environment_variables(variables) do
        # with_open_io([stdin , 'r'], [stdout, 'w'], [stderr, 'w'], [status, 'w']) do
        with_open_io([stdin , 'r'], [stdout, 'w'], [stderr, 'w']) do
          # |stdin, stdout, stderr, status|
          |stdin, stdout, stderr|
          logger.debug "Redirecting IO for rake command"
          with_redirected_io(stdin, stdout, stderr) do
            tasks.each do |task_string|
              logger.debug "Preparing to invoke task '#{task_string}'"
              begin
                task_name, task_args = parse_task_string(task_string)
                task = Rake::Task[task_name]
                logger.debug "Invoking '#{task_name}'"
                task.invoke(*task_args)
                logger.debug "Reporting success status"
#                status.write_nonblock('S')
                report_status(status_path, 'S')
                begin
                  Process.kill("USR1", client_pid.to_i) if client_pid
                rescue Errno::ESRCH
                  # NOOP
                end
              rescue SignalException, SystemExit
                raise
              rescue Exception => error
                $stderr.puts "FAILED: '#{task_string}'"
                $stderr.puts "Error: #{error.message}"
                $stderr.puts "Backtrace:\n#{error.backtrace.join("\n")}"
                logger.debug "Reporting failure status"
                # status.write_nonblock('F')
                report_status(status, 'S')
                begin
                  Process.kill("USR2", client_pid.to_i) if client_pid
                rescue Errno::ESRCH
                  # NOOP
                end
              rescue
                status.close
              end
            end
          end
        end
      end
    end
  rescue EOFError
    # Do nothing
  end

  private

  # Modifed from rake.rb
  def collect_tasks_and_variables(args)
    tasks                       = []
    environment_variables       = {}
    args.each do |arg|
      if arg =~ /^(\w+)=(.*)$/
        environment_variables[$1] = $2
      else
        tasks << arg unless arg =~ /^-/
      end
    end
    tasks.push("default") if tasks.empty?
    [tasks, environment_variables]
  end

  # For each key value pair, yields an opened IO object
  def with_open_io(*files_to_modes)
    ios_to_close = []
    open_ios = files_to_modes.inject([]) do |ios, (ios_or_path, mode)|
      case ios_or_path
      when String, Pathname
        new_ios = open(ios_or_path, mode)
        ios.push(new_ios)
        ios_to_close.push(new_ios)
      when IO
        ios.push(ios_or_path)
      else
        raise "Don't know how to open #{ios_or_path.inspect}"
      end
      ios
    end
    yield(*open_ios)
  ensure
    ios_to_close.each do |file|
      file.close
    end
  end

  def with_environment_variables(variables)
    old_values = variables.inject({}) do |original, (name, variable)| 
      original[name.to_s] = ENV[name.to_s]
      ENV[name.to_s] = variable.to_s
      original
    end
    yield
  ensure
    (old_values || {}).each_pair do |name, value|
      if value.nil? then ENV.delete(name)
      else ENV[name] = value
      end
    end
  end

  # lifted from rake.rb
  def parse_task_string(string)
    if string =~ /^([^\[]+)(\[(.*)\])$/
      name = $1
      args = $3.split(/\s*,\s*/)
    else
      name = string
      args = []
    end
    [name, args]
  end

  # Clear Rake's memory of what has already been invoked
  def reenable_tasks!
    Rake.application.tasks.each do |task|
      task.reenable
    end
  end

  def report_status(path, status)
    file = Tempfile.new('rakeserver-status')
    file.puts(status)
    file.close
    FileUtils.mv(file.path, path)
  end

end
