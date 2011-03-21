require 'test_common'

class SchemaFree
  include Bud

  state do
    table :notes
    scratch :stats
    interface input, :send_me
    channel :msgs
    callback :got_msg
  end

  bloom do
    notes <= msgs.payloads
    msgs <~ send_me
    got_msg <= msgs
  end
end

class TestSFree < Test::Unit::TestCase
  def test_bloom
    p = SchemaFree.new
    p.run_bg

    q = Queue.new
    p.register_callback(:got_msg) do
      q.push(true)
    end

    p.sync_do {
      p.send_me <+ [[p.ip_port, [[123, 1], 'what a lovely day']]]
    }
    p.sync_do {
      p.send_me <+ [[p.ip_port, [[123, 2], "I think I'll go for a walk"]]]
    }

    # Wait for two messages
    2.times { q.pop }

    p.stop_bg
    assert_equal(2, p.notes.length)
    assert_equal(123, p.notes.first.key[0])
    assert_equal('what a lovely day', p.notes.first.val)
  end
end
