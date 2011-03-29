require 'test_common'
require 'stringio' 


class TerminalTester
  include Bud
  state do
    scratch :saw_input
  end

  bloom do
    saw_input <= stdio
  end
end

class TestTerminal < Test::Unit::TestCase
  def test_stdin
    $stdin = StringIO.new("I am input from stdin\n")
    q = Queue.new
    t = TerminalTester.new(:read_stdin => true)
    t.run_bg
    t.register_callback(:saw_input) do |tbl|
      assert_equal(1, tbl.length)
      q.push(true)
    end
    q.pop
    t.stop_bg
  end
end
