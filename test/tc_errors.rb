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

    bloom do
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

    bloom do
      t2 <= t1
    end
  end

  def test_missing_table_error
    assert_raise(Bud::CompileError) { MissingTable.new }
  end

  class PrecedenceError
    include Bud

    state do
      table :foo
      table :bar
      table :baz
    end

    bloom do
      foo <= baz
      # Mistake: <= binds more tightly than "or"
      foo <= (bar.first and baz.first) or []
    end
  end

  def test_precedence_error
    assert_raise(Bud::CompileError) { PrecedenceError.new }
  end

  class VarShadowError
    include Bud

    state do
      table :t1
      table :t2
    end

    bloom do
      temp :t2 <= join([t1, t1])
    end
  end

  def test_var_shadow_error
    assert_raise(Bud::CompileError) { VarShadowError.new }
  end
end
