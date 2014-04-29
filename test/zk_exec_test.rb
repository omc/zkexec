gem "minitest"
require "minitest/autorun"
require "minitest/spec"
require "socket"
require "zk"
include Process
require "timeout"
include Timeout

TCPSocket.new("localhost", 2181).close \
  rescue abort "No zookeeper running, please start a local one!"

ZKEXEC = File.expand_path(File.join(File.dirname(__FILE__), "..", "bin", "zkexec"))
CHECK = File.expand_path(File.join(File.dirname(__FILE__), "libexec", "slowcheck"))
CHILDREN = []

zk = ZK.new
zk.create("/zkexec-test", "") rescue nil

def pids 
  system "ps aux | fgrep 'nc -l' | fgrep -v fgrep | fgrep -v health"
  `ps aux | fgrep 'nc -l' | fgrep -v fgrep | fgrep -v health | awk '{print $2}'`.
    strip.split(/\s+/).map(&:to_i)
end

describe "zkexec" do
  it "should fail when run without args" do
    system("#{ZKEXEC} >/dev/null").must_equal(false)
  end
  
  it "should run with exec" do # note this is /usr/bin/true or equivalent
    system("#{ZKEXEC} --silent --exec true").must_equal(true)
  end
  
  it "should keep the inner response code" do # note this is /usr/bin/false or equivalent
    system("#{ZKEXEC} --silent --exec false").must_equal(false)
  end
  
  it "should alert on failure" do
    `#{ZKEXEC} --silent --exec false --alert 'echo FOO'`.must_match(/FOO/)
  end
  
  it "should rolling restart" do
    begin
      cmd = <<-CMD
        #{ZKEXEC} --exec 'nc -l 4000' 
                  --health '#{CHECK} 2181 2'
                  --health-delay 2
                  --health-interval 1
                  --lock foo
                  --mirror /tmp/zkexec-test=/zkexec-test
      CMD
      
      if pids().size > 0
        raise "stray nc processes on system will interfere with tests"
      end
      
      cmd.gsub!(/\s+/, " ")
      cmd.strip!
      CHILDREN << a = fork { exec cmd }
      CHILDREN << b = fork { exec cmd }
      
      sleep 2

      timeout(10) do

        original = pids()
        remaining = original.size

        zk.set("/zkexec-test", rand.to_s)
      
        # Test that the pids get replaced one at a time
        while remaining > 0
          previous = remaining
          current = pids()
          puts current.inspect
          remaining = (original & current).size
          puts remaining.inspect
          puts previous.inspect
          (remaining - previous).must_be :<, 2
          sleep 0.5
        end
    
        while pids().size < original.size
          sleep 0.5
        end
      end
    ensure
      (CHILDREN + pids).map {|c| puts "killing #{c}" ; kill("KILL", c)}
    end
  end
end