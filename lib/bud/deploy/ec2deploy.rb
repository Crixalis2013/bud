require 'rubygems'
require 'AWS'
require 'pp'
require 'net/ssh'
require 'net/scp'
require 'bud'
require 'bud/deploy/deployer'

module EC2Deploy
  include Deployer

  state do
    table :access_key_id, [] => [:key]
    table :secret_access_key, [] => [:key]
    table :image_id, [] => [:img]
    table :key_name, [] => [:name]
    table :ec2_key_location, [] => [:loc]
    table :ec2_conn, [] => [:conn]
    table :ec2_insts, [] => [:insts]
    table :reservation_id, [] => [:rid]
    periodic :spinup_timer, 6
    scratch :the_reservation, [] => [:reservation]
    scratch :the_reservation_next, [] => [:reservation]
    scratch :node_up, [:node] => [:bool]
    table :init_dir, [] => [:dir]
    table :temp_node, [:uid, :node, :localip]
    table :all_up, [:bool]
    table :ruby_command, [] => [:cmd]
    table :deploy_node, [:uid] => [:node]
    # XXX: uncomment this when we update the AMI's gem
#    channel :ready, [:@loc, :sender]
    table :ready_tab, [:sender]
    scratch :ready_count, [:num]
  end

  deploystrap do
    # Write the IP & port to a file; we'll send this to each EC2 node.
    File.open("deploy_ip_port", "w") do |f|
      f.puts ip_port
    end
  end

  bootstrap do
    # The official BUD AMI.
    image_id <= [["ami-f434c99d"]]
    # XXX: uncomment this when we update the AMI's gem
#    unless @options[:deploy]
#      # Send message to the deployer telling 'em we's up.
#      File.open("deploy_ip_port", "r") do |f|
#        ready <~ [[f.readline.chop, ip_port]]
#      end
#    end
  end

  bloom :spinup do
    ec2_conn <= join([access_key_id, secret_access_key]).map do
      if idempotent [:ec2_comm]
        [AWS::EC2::Base.new(:access_key_id => access_key_id[[]].key,
                            :secret_access_key => secret_access_key[[]].key)]
      end
    end

    ec2_insts <= join([image_id, node_count, key_name, ec2_conn]).map do
      if idempotent [:ec2_insts]
        print "Starting up EC2 instances"
        STDOUT.flush
        # First, we create the security group.
        begin
          ec2_conn[[]].conn.create_security_group(:group_name => "bud", :group_description => "bud")
        rescue AWS::InvalidGroupDuplicate
          # Group already exists; ok, maybe we created it previously.
        else
          # Add SSH permission.
          ec2_conn[[]].conn.authorize_security_group_ingress( :group_name => "bud",
                                                              :ip_protocol => "tcp",
                                                              :from_port => 22,
                                                              :to_port => 22,
                                                              :cidr_ip => "0.0.0.0/0" )
          # Add unlimited UDP permission from any node not in the security group.
          # XXX: make this more restrictive?
          ec2_conn[[]].conn.authorize_security_group_ingress( :group_name => "bud",
                                                              :ip_protocol => "udp",
                                                              :from_port => 0,
                                                              :to_port => 65535,
                                                              :cidr_ip => "0.0.0.0/0" )
        end

        # Finally, start up the instances.
        [ec2_conn[[]].conn.run_instances(:image_id => image_id[[]].img,
                                         :min_count => node_count[[]].num,
                                         :max_count => node_count[[]].num,
                                         :key_name => key_name[[]].name,
                                         :security_group => "bud")]
      end
    end

    the_reservation <= join([spinup_timer, ec2_conn, ec2_insts]).map do |t,c,i|
      if idempotent [[:the_reservation, t.val]] and not all_up.include? [true]
        to_ret = nil
        begin
          to_ret = [ec2_conn[[]].conn.describe_instances()["reservationSet"]["item"].find do |i|
                      i["reservationId"] == ec2_insts[[]].insts["reservationId"]
                    end]
        rescue SocketError
          print "E"
        else
          print "."
        end
        STDOUT.flush
        to_ret
      end
    end

    # XXX: No upsert operator, so we have to do this.
    the_reservation_next <+ the_reservation

    node_up <= ((join([ec2_insts, the_reservation]).map do
                   if not all_up.include? [true]
                     the_reservation[[]].reservation["instancesSet"]["item"].map do |i|
                       [i, i["instanceState"]["code"] == "16"]
                     end
                   end
                 end)[0] or [])


    all_up <+ node_up.map do
      if node_up.find {|n| n.bool == false} == nil and node_up.find {|n| n.bool == true} != nil
        if idempotent [:nodes_all_up]
          puts "done"
          STDOUT.flush
          [true]
        end
      end
    end

    # XXX: Fixed port 54321
    temp_node <= join([all_up, the_reservation_next]).map do
      break(((0..(the_reservation_next[[]].reservation["instancesSet"]["item"].size-1)).to_a.zip(the_reservation_next[[]].reservation["instancesSet"]["item"].map {|i| [i["ipAddress"], i["privateIpAddress"]]})).map {|n,ips| [n, ips[0] + ":54321", ips[1] + ":54321"]})
    end

    deploy_node <= join([temp_node, init_dir, ruby_command]).map do |t, i, r|
      if idempotent [[:node_startup, t.node]]
        ip = t.node.split(":")[0]
        port = t.node.split(":")[1]
        print "Deploying to #{ip} (#{t.uid}/#{node_count[[]].num-1})."
        STDOUT.flush

        # Upload files and run commands.
        ctr = 0
        while ctr < 10
          begin
            Net::SSH.start(ip, 'ec2-user', :keys => [ec2_key_location[[]].loc],
                           :timeout => 5, :paranoid => false) do |session|
              session.scp.upload!("deploy_ip_port", "/home/ec2-user")
              session.scp.upload!(init_dir[[]].dir, "/home/ec2-user",
                                  :recursive  => true)
              session.exec!('nohup ' + ruby_command[[]].cmd + ' ' + t.localip +
                           ' ' + ip + ' >metarecv.out 2>metarecv.err </dev/null &')
            end
            break true
          rescue Exception
            ctr += 1
            print "."
            STDOUT.flush
            sleep 10
            next
          end
        end or raise "EC2 SSH failed after 10 retries"

        puts "done"
        [t.uid, t.node]
      end
    end

  end

  bloom :all_nodes do
    stdio <~ ready.map {|_,s| ["Ready: #{s}"]}
    # Persist ready messages
    ready_tab <= ready.map {|_, s| [s]}
    # Compute a count of ready messages
    ready_count <= ready_tab.group(nil, count)
    # Copy deploy_node into node when all nodes are up
    node <= join([ready_count, node_count],
                 [ready_count.num, node_count.num]).map do
      break deploy_node
    end

  end

end
