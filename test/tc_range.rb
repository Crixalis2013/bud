require './test_common'

class RangeCollection
  include Bud

  state do
    range :foo, [:addr, :$id]
    range :bar, [:addr, :$id]
  end

  bootstrap do
    foo <= [["xyz", 1], ["xyz", 2], ["xyz", 3]]
  end

  bloom do
    bar <= foo {|f| [f.addr, f.id + 1]}
  end
end

class TestRangeCollection < MiniTest::Unit::TestCase
  def test_insert
    r = RangeCollection.new
    r.tick
    assert(!r.foo.empty?)
    assert_equal([["xyz", 1], ["xyz", 2], ["xyz", 3]].to_set,
                 r.foo.to_set)
    assert_equal([["xyz", 2], ["xyz", 3], ["xyz", 4]].to_set,
                 r.bar.to_set)
  end
end

class TestMultiRange < MiniTest::Unit::TestCase
  def test_random_dense
    digits = 0.upto(100).to_a
    100.times do
      input = digits.shuffle
      mr = Bud::MultiRange.new(input.shift)
      input.each {|i| mr << i}
      assert_equal(digits, mr.to_a)
      assert_equal(1, mr.nbuckets)
    end
  end

  def test_random_sparse
    digits = 0.upto(100).select {|d| d % 2 == 1}
    100.times do
      input = digits.shuffle
      mr = Bud::MultiRange.new(input.shift)
      input.each {|i| mr << i}
      assert_equal(digits, mr.to_a)
      assert_equal(digits.size, mr.nbuckets)
    end
  end
end
