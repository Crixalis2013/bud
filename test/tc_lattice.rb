require './test_common'

class SimpleMax
  include Bud

  state do
    lmax :m
    lbool :done
  end

  bloom do
    done <= m.gt(12)
  end
end

class MaxOfMax
  include Bud

  state do
    scratch :in_t, [:v]
    lmax :m1
    lmax :m2
    lmax :m3
    lbool :done
  end

  bloom do
    m1 <= in_t {|t| t[0] if t[0] % 2 == 0}
    m2 <= in_t {|t| t[0] if t[0] % 2 == 1}
    m3 <= m1
    m3 <= m2
    done <= m3.gt(20)
  end
end

class TestMax < MiniTest::Unit::TestCase
  def test_simple
    i = SimpleMax.new
    %w[m done].each {|r| assert_equal(0, i.collection_stratum(r))}
    i.m <+ Bud::MaxLattice.new(5)
    i.m <+ Bud::MaxLattice.new(10)
    i.tick
    assert_equal(false, i.done.current_value.reveal)
    i.m <+ Bud::MaxLattice.new(13)
    i.tick
    assert_equal(true, i.done.current_value.reveal)
  end

  def test_simple_implicit_merge
    i = SimpleMax.new
    %w[m done].each {|r| assert_equal(0, i.collection_stratum(r))}
    i.m <+ [5, 10]
    i.tick
    assert_equal(false, i.done.current_value.reveal)
    i.m <+ [13]
    i.tick
    assert_equal(true, i.done.current_value.reveal)
  end

  def test_max_of_max
    i = MaxOfMax.new
    %w[in_t m1 m2 m3 done].each {|r| assert_equal(0, i.collection_stratum(r))}
    i.in_t <+ [[4], [6], [7]]
    i.tick
    assert_equal(false, i.done.current_value.reveal)
    i.in_t <+ [[22], [19]]
    i.tick
    assert_equal(true, i.done.current_value.reveal)
    i.in_t <+ [[2], [3], [23]]
    i.tick
    assert_equal(true, i.done.current_value.reveal)
  end
end
