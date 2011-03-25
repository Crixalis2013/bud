require 'test_common'

class StarJoin
	include Bud
	state do
		table :r1
		table :r2, [:key] => [:vat]
		table :r3
		table :r4
		table :r5
		table :r51
		table :r52
		table :r6
		table :r7
		table :r8
		table :r9
		table :r10
		table :r11
		table :r12
	end
	
	bootstrap do
		r1 <= [[1,1]]
		r2 <= [[1,2],[3,4]]
	end
	
	bloom do
		r3 <= (r1*r2).pairs {|r,s| [s.vat, r.key]}
		r4 <= join([r1,r2]) {|r,s| [s.vat, r.key]}
		r5 <= (r1*r2).pairs(:val => :key) {|r,s| [r.key, s.vat]}
		r51 <= (r1*r2).pairs([r1.val,r2.key]) {|r,s| [r.key, s.vat]}
		r52 <= (r1*r2).pairs(r2.key => r1.val) {|r,s| [r.key, s.vat]}
		r6 <= join([r1,r2], [r1.val,r2.key]) {|r,s| [r.key, s.vat]}
		r7 <= (r1*r2).matches {|r,s| [r.key, s.vat]}
		r8 <= natjoin([r1,r2]) {|r,s| [r.key, s.vat]}
		r9 <= (r1*r2).lefts(:val => :key)
		r10 <= join([r1,r2], [r1.val,r2.key]) {|r,s| r}
		r11 <= (r1*r2).rights(:val => :key)
		r12 <= join([r1,r2], [r1.val,r2.key]) {|r,s| s}
	end
end

class StarJoin3
  include Bud

  state do
		table :t1
		table :t2
		table :t3
		table :r1, [:k4] => [:v4]
		table :r2, [:k5] => [:v5]
		table :r3, [:k6] => [:v6]
		table :t4, [:k1,:v1,:k2,:v2,:k3,:v3]
		table :t5, [:k1,:v1,:k2,:v2,:k3,:v3]
  end

  bootstrap do
    t1 <= [['A', 'B']]
    t2 <= [[3,4]]
		t3 <= [['A', 'Y']]
    r1 <= [['A', 'B']]
    r2 <= [[3,4]]
		r3 <= [['A', 'Y']]		
  end

  bloom do
    t4 <= (r1 * r2 * r3).pairs(:k4 => :k6) {|r,s,t| r+s+t}
		t5 <= join([t1,t2,t3],[t1.key,t3.key]).map{|r,s,t| r+s+t}
  end
end

class MixedAttrRefs
	include Bud
	state do
		table :r1
		table :r2
		table :r3
	end
	
	bloom do
		r3 <= (r1*r2).pairs(:key => r2.val)
	end
end

class MissingAttrRefs
	include Bud
	state do
		table :r1
		table :r2
		table :r3
	end
	
	bloom do
		r3 <= (r1*r2).pairs(:i_dont_exist => :ha)
	end
end

class IllegalAttrRefs
	include Bud
	state do
		table :r1
		table :r2
		table :r3
	end
	
	bloom do
		r3 <= (r1*r2).pairs("key" => "val")
	end
end

class AmbiguousAttrRefs
	include Bud
	state do
		table :r1
		table :r2
		table :r3
	end
	
	bloom do
		temp :r4 <= (r1*r2*r3).pairs(:key => :val)
	end
end


class CombosBud
  include Bud

  state {
    table :r, [:x, :y1]
    table :s_tab, [:x, :y1]
    table :t, [:x, :y1]
    table :mismatches, [:x, :y1]
    scratch :simple_out, [:x, :y1, :y2]
    scratch :match_out, [:x, :y1, :y2]
    scratch :chain_out, [:x1, :x2, :x3, :y1, :y2, :y3]
    scratch :flip_out, [:x1, :x2, :x3, :y1, :y2, :y3]
    scratch :nat_out, [:x1, :x2, :x3, :y1, :y2, :y3]
    scratch :loj_out, [:x1, :x2, :y1, :y2]
  }

  bloom do
    r << ['a', 1]
    r << ['b', 1]
    r << ['b', 2]
    r << ['c', 1]
    r << ['c', 2]
    s_tab << ['a', 1]
    s_tab << ['b', 2]
    s_tab << ['c', 1]
    s_tab << ['c', 2]
    t << ['a', 1]
    t << ['z', 1]
    mismatches << ['a', 1]
    mismatches << ['v', 1]
    mismatches << ['z', 1]

    temp :j <= join([r,s_tab], [r.x, s_tab.x])
    simple_out <= j.map { |t1,t2| [t1.x, t1.y1, t2.y1] }

    temp :k <= join([r,s_tab], [r.x, s_tab.x], [r.y1, s_tab.y1])
    match_out <= k.map { |t1,t2| [t1.x, t1.y1, t2.y1] }

    temp :l <= join([r,s_tab,t], [r.x, s_tab.x], [s_tab.x, t.x])
    chain_out <= l.map { |t1, t2, t3| [t1.x, t2.x, t3.x, t1.y1, t2.y1, t3.y1] }

    temp :m <= join([r,s_tab,t], [r.x, s_tab.x, t.x])
    flip_out <= m.map { |t1, t2, t3| [t1.x, t2.x, t3.x, t1.y1, t2.y1, t3.y1] }

    temp :n <= natjoin([r,s_tab,t])
    nat_out <= n.map { |t1, t2, t3| [t1.x, t2.x, t3.x, t1.y1, t2.y1, t3.y1] }

    temp :newtab <= (r * s_tab * t).combos(r.x => s_tab.x, s_tab.x => t.x)
    temp :newtab_out <= newtab { |a,b,c| [a.x, b.x, c.x, a.y1, b.y1, c.y1] }	

    temp :loj <= leftjoin([mismatches, s_tab], [mismatches.x, s_tab.x])
    loj_out <= loj.map { |t1, t2| [t1.x, t2.x, t1.y1, t2.y1] }
  end
end

# Check that assignment operators within nested blocks aren't confused for a
# join alias -- Issue #82.
class BlockAssign
  include Bud

  state do
    table :num, [:num]
  end

  bloom do
    num <= (1..5).map do |i|
      foo = i
      [foo]
    end
  end
end

# Check that "<<" within a nested block isn't confused for a Bloom op (#84).
class BlockAppend
  include Bud

  state do
    table :num, [:num]
  end

  bloom do
    num <= (1..5).map do |i|
      foo = []
      foo << i
    end
  end
end

class TestJoins < Test::Unit::TestCase
  def test_combos
    program = CombosBud.new
    assert_nothing_raised(RuntimeError) { program.tick }
    simple_outs = program.simple_out
    assert_equal(7, simple_outs.length)
    assert_equal(1, simple_outs.select { |t| t[0] == 'a'} .length)
    assert_equal(2, simple_outs.select { |t| t[0] == 'b'} .length)
    assert_equal(4, simple_outs.select { |t| t[0] == 'c'} .length)
  end

  def test_secondary_join_predicates
    program = CombosBud.new
    assert_nothing_raised(RuntimeError) { program.tick }
    match_outs = program.match_out
    assert_equal(4, match_outs.length)
    assert_equal(1, match_outs.select { |t| t[0] == 'a'} .length)
    assert_equal(1, match_outs.select { |t| t[0] == 'b'} .length)
    assert_equal(2, match_outs.select { |t| t[0] == 'c'} .length)
  end

  def test_3_joins
    program = CombosBud.new
    assert_nothing_raised(RuntimeError) { program.tick }
    chain_outs = program.chain_out.to_a
    assert_equal(1, chain_outs.length)
    flip_outs = program.flip_out.to_a
    assert_equal(1, flip_outs.length)
    nat_outs = program.nat_out
    assert_equal(1, nat_outs.length)
    assert_equal(chain_outs, flip_outs)
		assert_equal(chain_outs, program.newtab_out.to_a)
  end

  def test_block_assign
    program = BlockAssign.new
    program.tick
    assert_equal([1,2,3,4,5], program.num.to_a.sort.flatten)
  end

  def test_block_append
    program = BlockAppend.new
    program.tick
    assert_equal([1,2,3,4,5], program.num.to_a.sort.flatten)
  end

  def test_left_outer_join
    program = CombosBud.new
    assert_nothing_raised(RuntimeError) { program.tick }
    loj_outs = program.loj_out
    assert_equal(3, loj_outs.length)
    assert_equal(loj_outs.to_a.sort, [["a", "a", 1, 1], ["v", nil, 1, nil], ["z", nil, 1, nil]])
  end

	def test_star_join
		program = StarJoin.new
		assert_nothing_raised(RuntimeError) { program.tick }
		assert_equal(program.r3.to_a.sort, program.r4.to_a.sort)
		assert_equal([[2,1],[4,1]], program.r3.to_a.sort)
		assert_equal(program.r5.to_a.sort, program.r6.to_a.sort)
		assert_equal(program.r5.to_a.sort, program.r51.to_a.sort)
		assert_equal(program.r5.to_a.sort, program.r52.to_a.sort)
		assert_equal([[1,2]], program.r5.to_a.sort)
		assert_equal(program.r7.to_a.sort, program.r8.to_a.sort)
		assert_equal([[1,2]], program.r7.to_a.sort)
		assert_equal(program.r9.to_a.sort, program.r10.to_a.sort)
		assert_equal([[1,1]], program.r9.to_a.sort)
		assert_equal([[1,2]], program.r11.to_a.sort)
		assert_equal(program.r11.to_a.sort, program.r12.to_a.sort)
	end
	
	def test_star_join3
    program = StarJoin3.new
    assert_nothing_raised(RuntimeError) {program.tick}
    assert_equal([['A','B',3,4,'A','Y']], program.t4.to_a)
    assert_equal(program.t4.to_a, program.t5.to_a)
  end
	
	def test_bad_star_joins
		p1 = MixedAttrRefs.new
		p2 = MissingAttrRefs.new
		p3 = IllegalAttrRefs.new
		p4 = AmbiguousAttrRefs.new
		assert_raise(Bud::CompileError) {p1.tick}
		assert_raise(Bud::CompileError) {p2.tick}
		assert_raise(Bud::CompileError) {p3.tick}
		assert_raise(Bud::CompileError) {p4.tick}
	end
end
