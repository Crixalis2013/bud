# simple chat
require 'rubygems'
require 'bud'
require 'chat_protocol'

class ChatServer
  include Bud
  include ChatProtocol

  state { table :nodelist }

  bloom :master_logic do
    nodelist <= signup.payloads
    mcast <~ join([mcast, nodelist]) do |m,n| 
      [n.key, m.val] unless n.key == m.val[0]
    end
  end
end

ip, port = ARGV[0].split(':')
program = ChatServer.new({:ip => ip, :port => port.to_i})
program.run