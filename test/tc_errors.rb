require 'test_common'

class TestErrorHandling < Test::Unit::TestCase
  class EmptyBud
    include Bud
  end

  def test_do_sync_error
    b = EmptyBud.new
    b.run_bg
    assert_raise(Bud::BudError) { b.run_fg }
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

  class BadSchemy
    include Bud

    state do
      table :num, ["key"] => []
    end
  end

  def test_bad_schemy
    assert_raise Bud::BudError do
      p = BadSchemy.new
      p.tick
    end
  end

  class SchemyConflict
    include Bud

    state do
      table :num, [:map] => []
    end
  end

  def test_schemy_conflict
    assert_raise Bud::BudError do
      p = SchemyConflict.new
      p.tick
    end
  end

  class EachFromBadSym
    include Bud
    
    state do
      table :joe
    end
  end
  
  def test_each_from_bad_sym
    p = EachFromBadSym.new
    p.tick
    assert_raise(Bud::BudError) { p.joe.each_from_sym([:bletch]) {} }
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
  
  def test_bloom_block_error
    defn = "class BloomBlockError\ninclude Bud\nbloom \"blockname\" do\nend\n\nend\n"
    assert_raise(Bud::CompileError) {eval(defn)}
  end
  
  def test_dup_blocks
    defn = "class DupBlocks\ninclude Bud\nbloom :foo do\nend\nbloom :foo do\nend\nend\n"
    assert_raise(Bud::CompileError) {eval(defn)}
  end

  class EvalError
    include Bud

    state do
      scratch :t1
      scratch :t2
    end

    bloom do
      t2 <= t1 { |t| [t.key, 5 / t.val]}
    end
  end

  def test_eval_error
    e = EvalError.new
    e.run_bg

    assert_raise(Bud::BudError) {
      e.sync_do {
        e.t1 <+ [[5, 0]]
      }
    }

    e.stop_bg
  end

  class BadGroupingCols
    include Bud
    
    state do
      table :t1
    end
    
    bootstrap do
      t1 << [1,1]
    end
    
    bloom do
      temp :t2 <= t1.group([:qi], min(:val))
    end
  end
  
  def test_bad_grouping_cols
    p = BadGroupingCols.new
    assert_raise(Bud::BudError) {p.tick}
  end
  
  class BadJoinCols
    include Bud
    state do
      table :t1
      table :t2
    end 
    bootstrap do
      t1 << [1,1]
      t2 << [2,2]
    end
    
    bloom do
      temp :out <= (t1*t2).pairs(:qi => :gollum)
    end
  end
  
  def test_bad_join_cols
    p = BadJoinCols.new
    assert_raise(Bud::CompileError) {p.tick}
  end
  
  class BadNextChannel
    include Bud
    state do
      channel :c1
    end
    bloom do
      c1 <+ [["doh"]]
    end
  end
  
  def test_bad_next_channel
    p = BadNextChannel.new
    assert_raise(Bud::BudError) {p.tick}
  end
  
  class BadStdio
    include Bud
    bloom do
      stdio <= [["phooey"]]
    end
  end
  
  def test_bad_stdio
    p = BadStdio.new
    assert_raise(Bud::BudError) {p.tick}
  end
  
  class BadFileReader
    include Bud
    state do
      file_reader :fd, '/tmp/foo'+Process.pid.to_s
    end
    bloom do
      fd <= [['no!']]
    end
  end
  
  def test_bad_file_reader
    File.open('/tmp/foo'+Process.pid.to_s, 'a')
    p = BadFileReader.new
    assert_raise(Bud::BudError) {p.tick}
  end
  
  class BadOp
    include Bud
    state do
      table :foo
      table :bar
    end
    bloom do
      foo + bar
    end
  end
  
  def ntest_bad_op
    b = BadOp.new
  end
end
