require File.expand_path("../lib/rake-server", File.dirname(__FILE__))
require File.expand_path("../lib/rake_server/redirectable", File.dirname(__FILE__))

include RakeServer::Redirectable

File.open('input.txt', 'w') do |input|
  input.write("hello from input.txt\n")
end

puts "Preparing to redirect"
File.open("input.txt", "r") do |input|
  File.open("output.txt", 'w') do |output|
    with_redirected_io(input, output, $stderr) do
      puts "This should go to STDOUT"
      $stderr.puts "This goes to STDERR"
      system("echo 'Hello from a subshell!'")
      text = gets
      puts "Input: #{text}"
    end
  end
end
puts "Finished with redirection"
