require './test_common'

class SimpleStrat
  include Bud

  state do
    table :t1
    table :t2
    table :t3
  end

  bloom do
    t2 <= t1 {|t| [t.key + 1, t.val + 1]}
    t3 <= t2.group([:key], max(:val))
  end
end

class WinMove
  include Bud
end

class PartHierarchy
  include Bud

  state do
    poset :part, [:id, :child]
    table :tested, [:id]
    scratch :working, [:id]
    scratch :has_suspect_part, [:id]
  end

  bloom do
    working <= tested
    working <= part {|p| [p.id]}.notin(has_suspect_part)
    has_suspect_part <= part.notin(working, :child => :id).pro {|p| [p.id]}
  end
end

class TestStrat < MiniTest::Unit::TestCase
  def test_simple_strat
    s = SimpleStrat.new
  end

  def test_part_hierarchy_unstrat
    assert_raises(Bud::CompileError) { PartHierarchy.new }
  end

  def test_part_hierarchy_manual_strat
    p = PartHierarchy.new(:stratum_map => {
                            "tested" => 0, "working" => 1,
                            "has_suspect_part" => 1, "part" => 0
                          })
    p.part <+ [["house", "kitchen"],
               ["house", "garage"],
               ["house", "bedroom"]]
    p.tick

    puts "WORKING: #{p.working.to_a.sort.inspect}"
    puts "SUSPECT_PART: #{p.has_suspect_part.to_a.sort.inspect}"
  end

  def test_win_move_unstrat
  end

  def test_win_move_manual_strat
  end
end

class TestPosetSimple
  include Bud

  state do
    poset :t1, [:x, :y]
    table :t2, t1.schema
  end

  bloom do
    t2 <= t1 {|t| [t.x + 1, t.y + 2]}
  end
end

class TestPoset < MiniTest::Unit::TestCase
  def test_poset_simple
    t = TestPosetSimple.new
    t.t1 <+ [[5, 1], [5, 2], [10, 5]]
    t.tick

    assert_equal([[6, 3], [6, 4], [11, 7]].to_set, t.t1.to_set)
  end
end
