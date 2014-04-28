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
      @zk = ZK.new(@cluster, :thread => :per_callback)
      raise "timeout connecting to #{@cluster}" unless @zk.connected?
      log "connected"
      
      # re-establish watches
      @on_connected ||= @zk.on_connected do
        @mirrors.each do |(local, remote)|
          watch(remote)
        end
      end
      
      @restart_lock = @lock_name && @zk.exclusive_locker(@lock_name)
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
        begin
          log "waiting on lock: #{@lock_name}"
          @restart_lock.lock(:wait => true)
          log "acquired lock: #{@lock_name}"
          yield
        ensure
          @restart_lock.unlock
          log "released lock: #{@lock_name}"
        end
      else
        yield
      end
    end
    
    private 
    def pid_exists?(pid)
      begin
        Process.getpgid(pid)
        true
      rescue Errno::ESRCH
        false
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
          checks_started = Time.now
          while pid_exists?(child) && Time.now - checks_started < 30
            sleep 1
          end
          if pid_exists?(child)
            log "force killing #{child}"
            Process.kill("KILL", child) 
          end

          log "#{child} terminated"
          
          # This intentionally infinite loops on failure, so that we don't propagate bad config
          health_checks_started = Time.now
          loop do
            log "waiting for health check success"
            if system(@health)
              log "health checks succeeding"
              return
            end
            if Time.now - health_checks_started > @health_delay
              log "health checks failing"
              alert
            end
            sleep @health_interval
          end
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
          if $?.exitstatus == 0
            log "successful health check"
          else
            log "failed health check, alerting"
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