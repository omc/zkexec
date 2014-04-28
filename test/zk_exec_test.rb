gem "minitest"
require "minitest/autorun"
require "minitest/spec"
require "socket"

TCPSocket.new("localhost", 2181).close \
  rescue abort "No zookeeper running, please start a local one!"

ZKEXEC = File.expand_path(File.join(File.dirname(__FILE__), "..", "bin", "zkexec"))

describe "zkexec" do
  it "should fail when run without args" do
    system("#{ZKEXEC}").must_equal(false)
  end
  
  it "should run with exec" do # note this is /usr/bin/true or equivalent
    system("#{ZKEXEC} --exec true").must_equal(true)
  end
  
  it "should keep the inner response code" do # note this is /usr/bin/false or equivalent
    system("#{ZKEXEC} --exec false").must_equal(false)
  end
  
  it "should alert on failure" do
    `#{ZKEXEC} --exec false --alert 'echo FOO'`.must_match(/FOO/)
  end
end