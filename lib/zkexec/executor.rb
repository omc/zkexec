require "zk"
require "thread"

module ZkExec
  class Executor
    include ZkExec
    include Process
    
    def initialize(options)
      @cmd         = options[:exec]
      @cluster     = options[:cluster]
      @health      = options[:health]
      @mirrors     = options[:mirrors]
      @alert       = options[:alert]
      @alert_delay = options[:alert_delay]
      @lock_name   = options[:lock]
      
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
      if @restart_lock
        log "waiting on lock: #{@lock_name}"
        @restart_lock.lock!
      end
      @local_lock.synchronize { yield }
    ensure
      if @restart_lock
        @restart_lock.unlock!
        log "released lock: #{@lock_name}"
      end
    end
    
    private 
    def kill_to_refork
      if @child
        with_restart_lock do
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
        end
      end
    end

    public
    def run
      Thread.new { execute }
    end

    def execute
      @should_refork = true
      while @should_refork
        log "forking #{@cmd}"
        @child = fork { exec @cmd }
        log "forked #{@child}"
        @should_refork = false
        wait @child
      end
    end
  end
end