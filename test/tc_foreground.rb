require 'test_common'
require 'timeout'

class Vacuous
  include Bud
end

class CallbackTest < Test::Unit::TestCase
  def test_111foreground1
    # note the test name.  we must run before all other tests, or run_fg will
    # throw "evenmachine already running" :(
    c = Vacuous.new
    assert_raise(Timeout::Error) do
      Timeout::timeout(0.1) do
        c.run_fg
      end
    end    
  end

  def test_11shutdown
    # similarly, this test must be run early, because it blocks if any eventmachines
    # are left running by other tests (which seems to be the case)
    c = Vacuous.new
    c.run_bg
    assert_nothing_raised {c.stop_bg(true)}
  end

  def test_already_running
    c1 = Vacuous.new
    c2 = Vacuous.new
    c1.run_bg
    assert_raise(Bud::BudError) {c2.run_fg}
    c1.stop_bg
  end

end

