require 'test_common'

class TickleCount
  include Bud

  state do
    channel :loopback, [:cnt]
    channel :mcast, [:@addr, :cnt]
    scratch :loopback_done, [:nums]
    scratch :mcast_done, [:nums]
  end

  bootstrap do
    loopback <~ [[0]]
  end

  bloom :count_to_5 do
    loopback <~ loopback {|l| [l.cnt + 1] if l.cnt < 6}
    loopback_done <= loopback {|l| [l.cnt] if l.cnt == 5}

    mcast <~ loopback {|l| [ip_port, l.cnt] if l.cnt < 6}
    mcast_done <= mcast {|m| [m.cnt] if m.cnt == 5}
  end
end

class TestTickle < Test::Unit::TestCase
  def test_tickle_count
    c = TickleCount.new
    q = Queue.new
    c.register_callback(:loopback_done) do |t|
      assert_equal([5], t.to_a.flatten)
      q.push(true)
    end
    c.register_callback(:mcast_done) do |t|
      assert_equal([5], t.to_a.flatten)
      q.push(true)
    end

    c.run_bg
    q.pop ; q.pop
    c.stop_bg
  end
end

class RingMember
  include Bud

  state do
    channel :pipe, [:@addr, :cnt]
    scratch :kickoff, [:cnt]
    table :next_guy, [:addr]
    table :last_cnt, [:cnt]
    scratch :done, [:cnt]
  end

  bloom :ring_msg do
    pipe <~ kickoff {|k| [ip_port, k.cnt]}
    pipe <~ (pipe * next_guy).pairs {|p,n| [n.addr, p.cnt + 1] if p.cnt < 39}
    done <= pipe {|p| [p.cnt] if p.cnt == 39}
  end

  bloom :update_log do
    last_cnt <+ pipe {|p| [p.cnt]}
    last_cnt <- (pipe * last_cnt).pairs {|p, lc| [lc.cnt]}
  end
end

class TestRing < Test::Unit::TestCase
  RING_SIZE = 10

  def test_basic
    ring = []
    RING_SIZE.times do |i|
      ring[i] = RingMember.new
      ring[i].run_bg
    end

    q = Queue.new
    ring.last.register_callback(:done) do
      q.push(true)
    end

    ring.each_with_index do |r, i|
      next_idx = i + 1
      next_idx = 0 if next_idx == RING_SIZE
      next_addr = ring[next_idx].ip_port

      r.sync_do {
        r.next_guy << [next_addr]
      }
    end

    first = ring.first
    first.async_do {
      first.kickoff <+ [[0]]
    }

    # Wait for the "done" callback from the last member of the ring.
    q.pop

    ring.each_with_index do |r, i|
      # XXX: we need to do a final tick here to ensure that each Bud instance
      # applies pending <+ and <- derivations. See issue #50.
      r.sync_do
      r.stop_bg
      assert_equal([30 + i], r.last_cnt.first)
    end
  end
end

class ChannelWithKey
  include Bud

  state do
    channel :c, [:@addr, :k1] => [:v1]
    scratch :kickoff, [:addr, :v1, :v2]
    table :recv, c.key_cols => c.val_cols
    table :ploads
  end

  bloom do
    c <~ kickoff {|k| [k.addr, k.v1, k.v2]}
    recv <= c
    ploads <= c.payloads
  end
end

class ChannelAddrInVal
  include Bud

  state do
    channel :c, [:k1] => [:@addr, :v1]
    scratch :kickoff, [:v1, :addr, :v2]
    table :recv, c.key_cols => c.val_cols
  end

  bloom do
    c <~ kickoff {|k| [k.v1, k.addr, k.v2]}
    recv <= c
  end
end

class TestChannelWithKey < Test::Unit::TestCase
  def test_basic
    p1 = ChannelWithKey.new
    p2 = ChannelWithKey.new

    q = Queue.new
    p2.register_callback(:recv) do
      q.push(true)
    end

    p1.run_bg
    p2.run_bg

    target_addr = p2.ip_port
    p1.sync_do {
      p1.kickoff <+ [[target_addr, 10, 20]]
      # Test that directly inserting into a channel also works
      p1.c <~ [[target_addr, 50, 100]]
    }

    # Wait for p2 to receive message
    q.pop

    p2.sync_do {
      assert_equal([[target_addr, 10, 20], [target_addr, 50, 100]], p2.recv.to_a.sort)
      assert_equal([[10, 20], [50, 100]], p2.ploads.to_a.sort)
    }

    # Check that inserting into a channel via <= is rejected
    assert_raise(Bud::BudError) {
      p1.sync_do {
        p1.c <= [[target_addr, 60, 110]]
      }
    }

    # Check that key constraints on channels are raised
    assert_raise(Bud::KeyConstraintError) {
      p1.sync_do {
        p1.c <~ [[target_addr, 70, 120]]
        p1.c <~ [[target_addr, 70, 130]]
      }
    }

    p1.stop_bg
    p2.stop_bg
  end
end

class TestChannelAddrInVal < Test::Unit::TestCase
  def test_addr_in_val
    p1 = ChannelAddrInVal.new
    p2 = ChannelAddrInVal.new

    q = Queue.new
    p2.register_callback(:recv) do
      q.push(true)
    end

    p1.run_bg
    p2.run_bg

    target_addr = p2.ip_port
    p1.sync_do {
      p1.kickoff <+ [[10, target_addr, 20]]
      # Test that directly inserting into a channel also works
      p1.c <~ [[50, target_addr, 100]]
    }

    # Wait for p2 to receive message
    q.pop

    p2.sync_do {
      assert_equal([[10, target_addr, 20], [50, target_addr, 100]], p2.recv.to_a.sort)
    }

    p1.stop_bg
    p2.stop_bg
  end
end

class ChannelBootstrap
  include Bud

  state do
    channel :loopback, [:foo]
    table :t1
    table :t2, [:foo]
  end

  bootstrap do
    loopback <~ [[1000]]
    t1 <= [[@ip, @port]]
  end

  bloom do
    t2 <= loopback
  end
end

class TestChannelBootstrap < Test::Unit::TestCase
  def test_bootstrap
    c = ChannelBootstrap.new
    q = Queue.new
    c.register_callback(:loopback) do
      q.push(true)
    end
    c.run_bg

    c.sync_do {
      t = c.t1.to_a
      assert_equal(1, t.length)
      v = t.first
      assert(v[1] > 1024)
      assert_equal(v[0], c.ip)
    }
    q.pop
    c.sync_do {
      assert_equal([[1000]], c.t2.to_a.sort)
    }
    c.stop_bg
  end
end
