require "zkexec/version"
require "zkexec/executor"
require "zkexec/runner"

require "zk"

module ZkExec
  def log(s) 
    STDERR.puts("[#{Time.now}] #{s}") unless $silent
  end
  
  def silence!
    $silent = true
  end
end
