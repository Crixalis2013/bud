require 'rubygems'
require 'bud'
require 'thread'

# Starts up a bunch of Bud instances locally on 127.0.0.1, with ephemoral ports.
# This is for the case where you just want to test stuff locally, but you don't
# really care about port numbers.
module LocalDeploy

  include BudModule

  state {
    table :node, [:uid] => [:node]
    table :node_count, [] => [:num]
    table :initial_data, [:uid, :data]
    channel :initial_data_chan, [:@node, :data]
    table :dead, [:dead]
    scratch :dont_care, [:dont_care]
  }

  # deal with SIGCHILD
  trap("CLD") {
    pid = Process.wait
    puts "Child pid #{pid}: terminated"
  }

  def initialize(opt)
    super
    if opt[:deploy]
      deploystrap
    end

    if opt[:nat]
      @my_ip = open("http://myip.dk") { |f| /([0-9]{1,3}\.){3}[0-9]{1,3}/.match(f.read)[0].to_a[0] }
    else
      @my_ip = @ip
    end
  end

  def deploystrap
    read, write = IO.pipe
    if node_count[[]] and idempotent [[:node]]
      (0..node_count[[]].num-1).map do |i|
        Process.fork do
          srand # don't want to inherit our parent's random stuff
          foo = self.class.new(:ip => '127.0.0.1')
          puts "Starting node " + i.to_s + "; pid " + Process.pid.to_s
          foo.run_bg
          # processes write their port to a pipe
          # for some reason, puts isn't atomic?
          write.print foo.port.to_s + "\n"
          EventMachine.reactor_thread.join
        end
      end
      # wait for all to be spun up
      (0..node_count[[]].num-1).map do |i|
        node << [i, "127.0.0.1:" + read.readline.rstrip]
      end
    end
  end

  # eval code in the bud instance
  def safe_eval(str, lambda)
    begin
      puts "Safe evaling: " + str
      $stdout.flush
      lambda.call(str)
    rescue Exception => exc
      puts "#{$!}"
      return false
    end
    return true
  end


  def me() @my_ip + ":" + @port.to_s end

  def idempotent(r) (dead.include? r) ? false : dead.insert(r) end

  # distribute the EDB to each node
  #
  # XXX: this may break coordination protocols that assume the EDB is present
  # before any messages are received.  In order to fix this, we would probably
  # need to globally synchronize to ensure that "timestamp 0" gets "fully
  # evaluated" before any messages can be sent
  declare
  def distribute_data
    initial_data_chan <~ join([node, initial_data],
                              [node.uid, initial_data.uid]).map do |n, i|
      [n.node, i.data] if idempotent [n,i]
    end

    dont_care <= initial_data_chan.each do |i|
      if idempotent i
        puts "Received all initial data; beginning computation"
        # XXX: mega hack here
        i.data.map do |j|
          j[1].map do |e|
            eval j[0].to_s + ".insert(" + e.inspect + ")"
          end
        end
      end
    end

  end
end
