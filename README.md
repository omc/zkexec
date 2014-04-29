# zkexec

zkexec is a wrapper around an executable that imports configuration from a zookeeper cluster.  When zookeeper configuration changes, zkexec syncs the configuration, then restarts the executable.  zkexec supports rolling restarts, health checks, and alerts.

## Tutorial

### Ante

1. Get a local zookeeper running on :2181 (the default port).
2. Checkout this git repo and cd into it.
3. Either `gem install zkexec`, or `bundle; export PATH=$PATH:bin`

### Calling zkexec

We'll start with the contrived example of running a script that acts just like cat, but it prefixes each line with the contents of a file:

    :$ echo -n hello > /tmp/prefix
    :$ echo world | ./test/libexec/prefixed-cat /tmp/prefix
    hello world

We want to run this in the console, such that we can type input in stdin, and get our prefixed output.  Here's the invokation (feel free to remove the --silent):

    :$ zkexec --silent --exec "./test/libexec/prefixed-cat /tmp/prefix"

This doesn't do anything special--it just wraps the execution.  Go ahead and run that, then type a few lines.  Ctrl-c away, check the return code.  It should behave just like `prefixed-cat`.

### Updating the config files

Let's put the prefix in zookeeper.  We'll throw it in the root, and use the --mirror flag to let zkexec know about it.

    :$ zookeeper/bin/zkCli.sh -cmd create /prefix hello
    :$ zkexec --silent \
         --exec "./test/libexec/prefixed-cat /tmp/prefix" \
         --mirror /tmp/prefix=/prefix
    world                                    # typed into stdin
    hello world                              # stdout    

So, now that we're tracking the config file, lets change it in another console.  Leave the existing terminal running.

    :$ zookeeper/bin/zkCli.sh -cmd set /prefix goodbye

Now, flip back to the original terminal and start typing.  You'll note that now the prefix is `goodbye`!

### Edge cases

#### What if you run a command that terminates?

zkexec will exit with the same error code.  Try it with ``/usr/bin/false`! (oh and I'll take this opportunity to show the default logs that show up on stderr when you don't pass the --silent flag)

    :$ zkexec --exec false # $ zkexec --exec false
    [2014-04-28 16:41:38 -0700] connecting to localhost:2181
    [2014-04-28 16:41:38 -0700] connected
    [2014-04-28 16:41:38 -0700] forking false
    [2014-04-28 16:41:38 -0700] forked 41804
    [2014-04-28 16:41:38 -0700] command failed
    :$ echo $?
    1

This means that you should have something (monit, etc) watching zkexec.  zkexec is not trying to be an all purpose monitoring solution.

### Adding health checks

A health check is simply an executable that returns 0 when the system is healthy, and non-zero otherwise.  For this tutorial, we'll use `./test/libexec/slowcheck`.  slowcheck takes two arguments, (1) the tcp port to check, and (2) the number of seconds to sleep before checking it.  If and only if the port is open, slowcheck will succeed.  The sleep will be useful later.

Let's append a health check to the previous command

    :$ zkexec \
         --exec "./test/libexec/prefixed-cat /tmp/prefix" \
         --mirror /tmp/prefix=/prefix \
         --health "./test/libexec/slowcheck 2181 1" \
         --health-delay 1 \
         --health-interval 1

The health-delay is the interval before the first health check (useful if your script is slow to start), and after the service starts, the health check will run every health-interval seconds.  It's up to you to make the health check script reasonable.  zkexec will happily run absurd scripts without timeouts, etc.

In this case, we're actually checking zookeeper's port. There's nothing special or required about that, it just happened to be convenient filler.

If you aren't running in silent mode, you'll see output like:

    [2014-04-28 16:51:07 -0700] connecting to localhost:2181
    [2014-04-28 16:51:07 -0700] connected
    [2014-04-28 16:51:07 -0700] registering callback on /prefix
    [2014-04-28 16:51:07 -0700] forking ./test/libexec/prefixed-cat /tmp/prefix
    [2014-04-28 16:51:07 -0700] forked 42333
    [2014-04-28 16:51:08 -0700] health checking via: ./test/libexec/slowcheck 2181 1
    [2014-04-28 16:51:09 -0700] successful health check
    [2014-04-28 16:51:10 -0700] health checking via: ./test/libexec/slowcheck 2181 1
    [2014-04-28 16:51:12 -0700] successful health check


### Adding alerts

An alert is simply an executable that gets called when a health check fails unexpectedly.  Alerts won't trigger within `health-delay` seconds of a restart.

Alerts are provided for your convenience.  In most cases, it's better to just add a dead man's switch to your health check.

#### A better alert scheme

Install a dead man's switch via monit via something similar to this sample code:

    :$ mkdir -p /var/run/foo
    :$ echo "check file succeeded\_at path /var/run/foo/succeeded\_at 
         if timestamp < 5 minutes then alert" > /etc/monit/conf.d/foo.conf
    :$ sudo monit reload 
    :$
    :$ zkexec \
         ...
         --health "./test/libexec/slowcheck 2181 1 && touch /tmp/succeeded_at" 

### Rolling restarts

Use `--lock NAME` to establish a rolling restart group.  When a config file changes, all wrapped processes sharing the lock name and the zookeeper cluster must acquire the lock before killing the child process.  A zkexec only releases the lock when health checks succeed or the zkexec parent process is killed.

Give it a try locally.  In this case, we'll use the slowness of the health check script to our advantage, because we can watch the restart execute serially via the timestamps of the logs.

Run two or more of the following command in separate terminals:

    :$ zkexec \
         --exec "./test/libexec/prefixed-cat /tmp/prefix" \
         --lock foo \
         --health "test/libexec/slowcheck 2181 10" \
         --mirror /tmp/prefix=/prefix \
         --health-delay 20 \
         --health-interval 1

Then, run the following:

    :$ zookeeper/bin/zkCli.sh -cmd set /prefix woot

You can watch the timestamps of the zkexec processes as they log on stdout, noting that they take turns restarting.

#### Config failures in rolling restart

A config failure during a restart is defined as either (1) the restarted process exiting non-zero, or (2) the restarted process failing health checks for `health-delay` seconds.

A config failure pauses the restart.  If this happens, you should push new config, and if it doesn't fail, the restart will pick up where it left off.

### All options

zkexec doesn't use config files.  All options are documented on the command line `--help`:

    :$ zkexec -h
    Usage: zkexec [options]

    Run a command, and restart if the config files change on the remote zookeeper.

        -e, --exec COMMAND               Run this command
        -c, --cluster HOST:PORT,...      Comma-delimited list of zookeeper hosts
        -H, --health COMMAND             Run this command to health-check
        -i, --health-interval INTERVAL   Health-check every INTERVAL seconds
        -d, --health-delay INTERVAL      Wait before starting health checks
        -m, --mirror LOCAL_PATH=ZK_PATH  Mirror a config file from zookeeper to localhost
        -l, --lock NAME                  Name of a zk lockfile, used to enforce rolling restarts
        -a, --alert COMMAND              Run this command if the primary command returns
                                         falsey or health checks fail for too long
        -v, --verbose
        -s, --silent
        -h, --help                       Show this message