require "optparse"

module ZkExec
  class Runner
    def initialize
    end

    def run(args)
      options = {:mirror => [], :quorum => 0}
      opts = OptionParser.new do |opts|
        opts.banner = "Usage: zkexec [options]\n\nRun a command, and restart if the config files change on the remote zookeeper.\n\n"

        opts.on("-e", "--exec COMMAND", "Run this command") do |s|
          options[:exec] = s
        end
        
        opts.on("-H", "--health COMMAND", "Run this command to health-check") do |s|
          options[:health] = s
        end
        
        opts.on("-m", "--mirror LOCAL_PATH=ZK_PATH", "Mirror a config file from zookeeper to localhost") do |s|
          options[:mirror] << s.split("=")
        end
        
        opts.on("-q", "--quorum COUNT", "Don't restart unless COUNT servers are healthy") do |s|
          options[:quorum] = s.to_i
        end
        
        opts.on("-a", "--alert COMMAND", "Run this command if the primary command returns","falsey or health checks fail for too long") do |s|
          options[:alert] = s
        end
        
        opts.on("-d", "--alert-delay SECONDS", "How long to wait for health checks to succeed") do |s|
          options[:alert_delay] = s.to_i
        end
        
        opts.on_tail("-h", "--help", "Show this message") do
          puts opts
          exit
        end
      end
      
      opts.parse!
      
      unless options[:exec]
        puts "Missing required option --exec.  See --help for usage."
        exit 1
      end
      
    end

    def join
      sleep 1<<31
    end
  end
end