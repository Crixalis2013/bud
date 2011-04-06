require 'rubygems'
require 'bud'
require 'tokenring'
require 'bud/deploy/ec2deploy'

# Mixes in quicksort with BinaryTreePartition
class RingLocal
  include Bud
  include TokenRing
  include EC2Deploy

  deploystrap do
    node_count << [10]
    eval(IO.read('keys.rb'), binding) if File.exists?('keys.rb')
    ruby_command << ["ruby tokenring-ec2.rb"]
    init_dir << ["."]
  end

end

ip, port = ARGV[0].split(':')
ext_ip, ext_port = ARGV[1].split(':')
RingLocal.new(:ip => ip,
              :ext_ip => ext_ip,
              :port => port,
              :ext_port => ext_port,
              :deploy => ARGV[2]).run_fg
