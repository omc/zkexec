require "zk"
require "thread"

module ZkExec
  class Executor
    include ZkExec
    include Process
    
    def initialize(options)
      @cmd             = options[:exec]
      @cluster         = options[:cluster]
      @health          = options[:health]
      @health_interval = options[:health_interval]
      @health_delay    = options[:health_delay]
      @mirrors         = options[:mirrors]
      @alert           = options[:alert]
      @lock_name       = options[:lock]
      
      log "connecting to #{@cluster}"
      @zk = ZK.new(@cluster, :timeout => 1, :retry_duration => 10)
      raise "timeout connecting to #{@cluster}" unless @zk.connected?
      log "connected"
      
      @restart_lock = @lock_name && @zk.locker(@lock_name)
      @local_lock = Mutex.new
      
      @mirrors.each do |(local, remote)|
        log "registering callback on #{remote}"
        @zk.register(remote) do |event|
          if event.changed?
            log "#{remote} changed"
            copy(local, remote)  
            kill_to_refork
          else
            watch(remote)  
          end
        end
        watch(remote)
      end
    end

    private 
    def copy(local, remote)
      data = watch(remote)
      File.open(local, "w") {|f| f.print(data) }
    rescue ZK::Exceptions::NoNode => e
      raise "node not found in #{e.message}"
    end
    
    private 
    def watch(remote)
      data, stat = *@zk.get(remote, :watch => true)
      return data
    rescue ZK::Exceptions::NoNode => e
      raise "node not found in #{e.message}"
    end
    
    private
    def with_restart_lock
      if @restart_lock && !@hold_lock_forever
        log "waiting on lock: #{@lock_name}"
        @restart_lock.lock!
      end
      @local_lock.synchronize { yield }
    ensure
      if @restart_lock && !@hold_lock_forever
        @restart_lock.unlock!
        log "released lock: #{@lock_name}"
      end
    end
    
    private 
    def kill_to_refork
      if @child
        with_restart_lock do
          if @health_checks
            Thread.kill(@health_checks) 
            @health_checks = nil
          end
          @should_refork = true
          child = @child
          @child = nil

          log "killing #{child}"
          Process.kill("TERM", child)

          start_waiting = Time.now
          while child.running? && Time.now - start_waiting < 30
            log "waiting on #{child}"
            sleep 1  
          end
          if child.running?
            log "force killing #{child}"
            Process.kill("KILL", child) 
          else
            log "#{child} terminated"
          end
          
          # wait for the other thread to bring the process back
          health_checks_started = Time.now
          while Time.now - health_checks_started < @health_delay
            if system(@health)
              @hold_lock_forever = false
              return
            end
            sleep 1
          end
          
          # not healthy, hang onto the lock forever, but still be
          # responsive to config file changes
          @hold_lock_forever = true
          alert
        end
      end
    end
    
    def alert 
      if @alert
        fork { exec(@alert) }
      end
    end
    
    def start_health_thread
      @health_checks ||= @health && Thread.new {
        sleep @health_delay
        loop do
          log "health checking via: #{@health}"
          pid = fork { exec(@health) }
          wait pid
          if $?.exitstatus != 0
            alert
          end
          sleep @health_interval
        end
      }
    end

    public
    def run
      Thread.new { execute }
    end

    def execute
      @should_refork = true
      
      while @should_refork
        start_health_thread
        log "forking #{@cmd}"
        @child = fork { exec @cmd }
        log "forked #{@child}"
        @should_refork = false
        wait @child
      end

      if $?.exitstatus != 0
        alert 
        raise "command failed"
      end
    end
  end
end