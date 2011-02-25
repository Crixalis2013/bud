require 'test_common'

class TestErrorHandling < Test::Unit::TestCase
  class EmptyBud
    include Bud
  end

  def test_do_sync_error
    b = EmptyBud.new
    b.run_bg
    assert_raise(Bud::BudError) { b.run }
    3.times {
      assert_raise(ZeroDivisionError) {
        b.sync_do {
          puts 5 / 0
        }
      }
    }

    b.stop_bg
  end

  class IllegalOp
    include Bud

    state do
      table :t1
    end

    declare
    def rules
      t1 < t1.map {|t| [t.key + 1, t.val + 1]}
    end
  end

  def test_illegal_op_error
    assert_raise(Bud::CompileError) { IllegalOp.new }
  end

  class MissingTable
    include Bud

    state do
      table :t1
    end

    declare
    def rules
      t2 <= t1
    end
  end

  def test_missing_table_error
    assert_raise(Bud::CompileError) { MissingTable.new }
  end
end
