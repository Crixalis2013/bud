require 'socket'

class Bud::BudServer < EM::Connection #:nodoc: all
  def initialize(bud)
    @bud = bud
    @pac = MessagePack::Unpacker.new
    super
  end

  def receive_data(data)
    # Feed the received data to the deserializer
    @pac.feed data

    # streaming deserialize
    @pac.each do |obj|
      message_received(obj)
    end

    begin
      @bud.tick_internal if @bud.running_async
    rescue Exception
      # If we raise an exception here, EM dies, which causes problems (e.g.,
      # other Bud instances in the same process will crash). Ignoring the
      # error isn't best though -- we should do better (#74).
      puts "Exception handling network messages: #{$!}"
      puts "Inbound messages:"
      @bud.inbound.each do |m|
        puts "    #{m[1].inspect} (channel: #{m[0]})"
      end
      @bud.inbound.clear
    end

    @bud.rtracer.sleep if @bud.options[:rtrace]
  end

  def message_received(obj)
    unless (obj.class <= Array and obj.length == 3 and
            @bud.tables.include?(obj[0].to_sym) and obj[1].class <= Array)
      raise Bud::Error, "bad inbound message of class #{obj.class}: #{obj.inspect}"
    end

    # Deserialize any nested lattice values
    tbl_name, tuple, lat_indexes = obj
    lat_indexes.each do |i|
      tuple[i] = Marshal.load(tuple[i])
      tuple[i].reset_exec_state # XXX: hack
      raise Bud::Error unless tuple[i].class <= BasicLattice
    end
    obj = [tbl_name, tuple]

    @bud.rtracer.recv(obj) if @bud.options[:rtrace]
    @bud.inbound << obj
  end
end
