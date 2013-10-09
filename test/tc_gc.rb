require './test_common'

class RseSimple
  include Bud

  state do
    table :sbuf, [:id] => [:val]
    scratch :res, sbuf.schema
    table :res_approx, sbuf.schema
  end

  bloom do
    res <= sbuf.notin(res_approx)
  end
end

class RseQual
  include Bud

  state do
    table :sbuf, [:id] => [:val]
    scratch :res, sbuf.schema
    table :sbuf_val_seen, [:val]
  end

  bloom do
    res <= sbuf.notin(sbuf_val_seen, :val => :val)
  end
end

class RseChainedNeg
  include Bud

  state do
    table :t0
    table :t1
    table :t2
    table :t3
    table :t4
    table :t5
    table :t6
  end

  bloom do
    # We can reclaim a tuple if it appears in t6 AND (t3 OR t4 OR r5)
    t0 <= t2.notin(t3).notin(t4).notin(t5)
    t1 <= t2.notin(t6)
  end
end

class RseNegateIntersect
  include Bud

  state do
    table :res1
    table :res2
    table :res3
    table :res4
    table :t2
    table :t3
    table :t4
    table :t5
    table :t6
  end

  bloom do
    # We can reclaim t2 tuples when they appear in _all of_ t3, t4, t5, and t6.
    res1 <= t2.notin(t3)
    res2 <= t2.notin(t4)
    res3 <= t2.notin(t5)
    res4 <= t2.notin(t6)
  end
end

# Check that we don't try to apply RSE on relation t if t appears in 1+ legal
# contexts and at least one illegal context.
class RseNegateIntersectDelete
  include Bud

  state do
    table :res1
    table :res2
    table :res3
    table :t2
    table :t3
    table :t4
    table :t5
    scratch :some_event
  end

  bloom do
    res1 <= t2.notin(t3)        # Okay
    res2 <= t2.notin(t4)        # Okay
    res3 <= t2.notin(t5)        # Not okay because t5 is deleted from
    t5 <- some_event
  end
end

# We can apply RSE to a rule even if the LHS collection of the rule is deleted
# from (or isn't persistent in the first place).
class RseDeleteDownstream
  include Bud

  state do
    table :t1
    table :t2
    table :t3
    scratch :some_event
  end

  bloom do
    t1 <= t2.notin(t3)
    t1 <- some_event
  end
end

class RseNegateScratchLhs
  include Bud

  state do
    table :t1
    table :t2
    table :t3
    scratch :r1
    scratch :r2
  end

  bloom do
    # Despite the fact that r2 is not persistent, we can reclaim t1 tuples once
    # they appear in both t2 and t3 -- because r2 is derived from t1 via
    # negating t1 against t3.
    r1 <= t1.notin(t2)
    r2 <= t1.notin(t3)
  end
end

class RseNegateScratchLhsBad
  include Bud

  state do
    table :t1
    table :t2
    scratch :r1
    scratch :r2
    scratch :r3
  end

  bloom do
    r1 <= t1.notin(t2)
    r2 <= t1.notin(r3)
  end
end

class RseNegateScratchLhsBad2
  include Bud

  state do
    table :t1
    table :t2
    table :t3
    scratch :r1
    scratch :r2
    scratch :r3
  end

  bloom do
    r1 <= t1.notin(t2)
    r2 <= t1.notin(t3).notin(r3)
  end
end

class RseNegateScratchLhsBad3
  include Bud

  state do
    table :t1
    table :t2
    scratch :r1
    scratch :r2
  end

  bloom do
    # We can't reclaim from t1, because that would cause r2 to shrink -- and we
    # regard r2 as potentially an "output" collection.
    r1 <= t1.notin(t2)
    r2 <= t1
  end
end

# Situations where a reference to the reclaimed relation on the RHS of a rule
# SHOULD NOT prohibit RSE.
class RseRhsRef
  include Bud

  state do
    table :t1
    table :t2
    table :t3
    table :t4
    table :t5
    table :t6
    table :t7
    scratch :s1
    scratch :s2
    scratch :res
  end

  bloom do
    # Via RSE (for a different table), we infer a deletion rule for the
    # downstream persistent table -- but since the rule is created by RSE, we
    # know it is "safe" and can be ignored.
    t6 <= t1
    s2 <= t6.notin(t7)
    res <= t1.notin(t2)

    # Other rules can have t1 on their RHS, provided they (a) are monotone (b)
    # derive into a persistent table.
    t3 <= t1                                                    # identity
    t4 <= t1 {|t| [t.key + 100, t.val + 100] if t.key < 100}    # sel, proj

    # t1 appears on the RHS of a rule that derives into a scratch, but the
    # output of the scratch is later persisted.
    s1 <= t1
    t5 <= s1
  end
end

# Situations where a reference to the reclaimed relation on the RHS of a rule
# SHOULD prohibit RSE.
class RseRhsRefBad
  include Bud

  state do
    table :t1
    table :t2
    table :t3
    table :t4
    table :t5
    table :t6, [:cnt]
    table :t7
    table :t8
    table :t9
    table :t10
    table :t11
    table :t12
    scratch :out
    scratch :some_event
    scratch :res
  end

  bloom do
    # Deletion from a persistent table
    res <= t1.notin(t2)
    t3 <= t1
    t3 <- some_event

    # Reference in a grouping/agg expression
    res <= t4.notin(t5)
    t6 <= t4.group(nil, count)

    # Reference as the outer (NM) operand to a notin
    res <= t7.notin(t8)
    t9 <= t10.notin(t7)

    # Dataflow reaches both a persistent and a transient-output collection. We
    # don't want to delete from t7 in this circumstance, because we regard the
    # content of "output" as needing to be preserved.
    res <= t11.notin(t12)
    t9 <= t11
    out <= t11
  end
end

class JoinRse
  include Bud

  state do
    table :node, [:addr, :epoch]
    table :sbuf, [:id] => [:epoch, :val]
    scratch :res, [:addr] + sbuf.cols
    table :res_approx, res.schema
  end

  bloom do
    res <= ((sbuf * node).pairs(:epoch => :epoch) {|s,n| [n.addr] + s}).notin(res_approx)
  end
end

class JoinRseVariantQuals
  include Bud

  state do
    table :node, [:addr, :epoch]
    table :sbuf, [:id] => [:epoch, :val]
    scratch :res, [:addr] + sbuf.cols
    table :res_approx, res.schema
  end

  bloom do
    res <= ((sbuf * node).pairs(node.epoch => sbuf.epoch) {|s,n| [n.addr] + s}).notin(res_approx)
  end
end

# RSE for joins with no join predicate -- i.e., cartesian products
class JoinRseNoQual
  include Bud

  state do
    table :node, [:addr]
    table :sbuf, [:id] => [:val]
    scratch :res, sbuf.cols + node.cols # Reverse column order for fun
    table :res_approx, res.schema
  end

  bloom do
    res <= ((sbuf * node).pairs {|s,n| s + n}).notin(res_approx)
  end
end

class JoinRseSealed
  include Bud

  state do
    sealed :node, [:addr]
    table :sbuf, [:id] => [:val]
    scratch :res, sbuf.cols + node.cols # Reverse column order for fun
    table :res_approx, res.schema
  end

  bootstrap do
    node <= [["foo"], ["bar"]]
  end

  bloom do
    res <= ((sbuf * node).pairs {|s,n| s + n}).notin(res_approx)
  end
end

class JoinRseNegationQual
  include Bud

  state do
    sealed :node, [:addr]
    table :sbuf, [:id] => [:val]
    scratch :res, [:addr, :id] => [:val]
    table :res_approx, res.key_cols + [:garbage]
  end

  bootstrap do
    node <= [["foo"], ["bar"]]
  end

  bloom do
    res <= ((node * sbuf).pairs {|n,s| n + s}).notin(res_approx, 0 => :addr, 1 => 1)
  end
end

class JoinRseNegationQualVariant
  include Bud

  state do
    sealed :node, [:addr]
    table :sbuf, [:id] => [:val]
    scratch :res, [:addr, :id] => [:val]
    table :res_approx, [:garbage] + res.key_cols
  end

  bootstrap do
    node <= [["foo"], ["bar"]]
  end

  bloom do
    res <= ((node * sbuf).pairs {|n,s| n + s}).notin(res_approx, 1 => :id)
  end
end

class JoinRseSealedUseTwice
  include Bud

  state do
    sealed :node, [:addr]
    channel :ins_chn, [:@addr, :id]
    channel :del_chn, [:@addr, :id]
    table :ins_log, [:id]
    table :del_log, [:id]
  end

  bloom do
    ins_chn <~ (node * ins_log).pairs {|n,l| n + l}
    del_chn <~ (node * del_log).pairs {|n,l| n + l}

    ins_log <= ins_chn.payloads
    del_log <= del_chn.payloads
  end
end

class JoinRseUseTwice
  include Bud

  state do
    sealed :node, [:addr, :epoch]
    channel :ins_chn, [:@addr, :id] => [:epoch]
    channel :del_chn, [:@addr, :id] => [:epoch]
    table :ins_log, [:id] => [:epoch]
    table :del_log, [:id] => [:epoch]
  end

  bloom do
    ins_chn <~ (node * ins_log).pairs(:epoch => :epoch) {|n,l| n + l}
    del_chn <~ (node * del_log).pairs(:epoch => :epoch) {|n,l| n + l}

    ins_log <= ins_chn.payloads
    del_log <= del_chn.payloads
  end
end

# Given sealed collection n that appears in two RSE-eligible join rules:
#
#   (n * # r).pairs.notin(...)
#   (n * s).pairs.notin(...)
#
# We only want to reclaim from n when we see seals for _both_ r and s.
# Naturally, the two joins might have different quals (and hence different
# sealing conditions).
class JoinRseSealDoubleReclaim
  include Bud

  state do
    sealed :node, [:addr, :epoch_x, :epoch_y]
    table :x_log, [:id, :epoch]
    table :y_log, [:id, :epoch]
    table :x_res, [:addr, :epoch_x, :epoch_y, :id, :epoch]
    table :y_res, x_res.schema
    table :x_res_approx, x_res.schema
    table :y_res_approx, x_res.schema
  end

  bloom do
    x_res <= ((node * x_log).pairs(:epoch_x => :epoch) {|n,x| n + x}).notin(x_res_approx)
    y_res <= ((node * y_log).pairs(:epoch_y => :epoch) {|n,y| n + y}).notin(y_res_approx)
  end
end

class JoinRseDoubleScratch
  include Bud

  state do
    table :obj, [:oid] => [:val]
    table :ref, [:id] => [:name, :obj_id]
    table :del_ref, [:id] => [:del_id]

    scratch :view, ref.cols + obj.cols
    scratch :view2, view.schema
  end

  bloom do
    view  <= ((ref * obj).pairs(:obj_id => :oid) {|r,o| r + o}).notin(del_ref, 0 => :del_id)
    view2 <= ((ref * obj).pairs(:obj_id => :oid) {|r,o| r + o}).notin(del_ref, 0 => :del_id)
  end
end

class JoinRseTlistConst
  include Bud

  state do
    table :a, [:c1, :c2, :c3]
    table :a_approx, a.schema
    table :b
    sealed :c
  end

  bloom :logic do
    a <= ((b * c).pairs {|t1,t2| [t1.key, "foo", t2.val]}).notin(a_approx)
    a <= ((b * c).pairs {|t1,t2| [t1.key, 99, t2.val]}).notin(a_approx)
  end
end

class JoinRseTlistIpPort
  include Bud

  state do
    table :a, [:c1, :c2, :c3, :c4]
    table :a_approx, a.schema
    table :b
    sealed :c
  end

  bloom :logic do
    a <= ((b * c).pairs {|t1,t2| [t1.key, ip_port, port, t2.val]}).notin(a_approx)
  end
end

class JoinRseTlistConstQual
  include Bud

  state do
    table :a, [:c1, :c2, :c3]
    table :a_approx, a.schema
    table :b
    sealed :c
  end

  bloom :logic do
    a <= ((b * c).pairs {|t1,t2| [t1.key, port, t2.val]}).notin(a_approx, 0 => :c1, 1 => :c2)
  end
end

class TestRse < MiniTest::Unit::TestCase
  def test_rse_simple
    s = RseSimple.new
    s.sbuf <+ [[5, 10], [6, 12]]
    s.tick
    s.res_approx <+ [[5, 10]]
    s.tick
    s.tick

    assert_equal([[6, 12]], s.sbuf.to_a.sort)
  end

  def test_rse_qual
    s = RseQual.new
    s.sbuf <+ [[1, 5], [2, 5], [3, 6]]
    s.tick
    assert_equal([[1, 5], [2, 5], [3, 6]].sort, s.res.to_a.sort)

    s.sbuf_val_seen <+ [[5]]
    s.tick
    s.tick

    assert_equal([[3, 6]], s.res.to_a.sort)
    assert_equal([[3, 6]], s.sbuf.to_a.sort)
  end

  def test_rse_chained_neg
    s = RseChainedNeg.new
    s.t2 <+ [[1, 1], [2, 2], [3, 3]]
    s.t3 <+ [[2, 2]]
    s.t4 <+ [[3, 3]]
    s.t6 <+ [[2, 2], [3, 3]]
    2.times { s.tick }

    assert_equal([[1, 1]], s.t2.to_a.sort)

    s.t2 <+ [[4, 4], [5, 5]]
    s.t5 <+ [[4, 4]]
    2.times { s.tick }

    assert_equal([[1, 1], [4, 4], [5, 5]], s.t2.to_a.sort)

    s.t2 <+ [[6, 6]]
    s.t3 <+ [[5, 5], [6, 6]]
    s.t6 <+ [[4, 4], [5, 5]]
    2.times { s.tick }

    assert_equal([[1, 1], [6, 6]], s.t2.to_a.sort)
  end

  def test_rse_negate_intersect
    s = RseNegateIntersect.new
    s.t2 <+ [[5, 10], [6, 11], [7, 12]]
    s.t3 <+ [[5, 10], [7, 12]]
    s.t4 <+ [[6, 11]]
    s.t5 <+ [[7, 12], [6, 11]]
    s.t6 <+ [[7, 12], [5, 10]]
    2.times { s.tick }

    assert_equal([[5, 10], [6, 11], [7, 12]], s.t2.to_a.sort)

    s.t2 <+ [[8, 13], [9, 14]]
    s.t3 <+ [[6, 11], [8, 13]]
    s.t4 <+ [[5, 10], [8, 13]]
    s.t5 <+ [[5, 10], [8, 13]]
    s.t6 <+ [[6, 11], [8, 13]]
    2.times { s.tick }

    assert_equal([[7, 12], [9, 14]], s.t2.to_a.sort)
  end

  def test_rse_negate_intersect_del
    s = RseNegateIntersectDelete.new
    s.t2 <+ [[5, 10], [6, 11], [7, 12]]
    s.t3 <+ [[5, 10]]
    s.t4 <+ [[6, 11]]
    s.t5 <+ [[7, 12]]
    2.times { s.tick }

    assert_equal([[5, 10], [6, 11], [7, 12]], s.t2.to_a.sort)

    s.t3 <+ [[6, 11], [7, 12]]
    s.t4 <+ [[5, 10], [7, 12]]
    s.t4 <+ [[5, 10], [6, 11]]
    2.times { s.tick }

    assert_equal([[5, 10], [6, 11], [7, 12]], s.t2.to_a.sort)
  end

  def test_rse_delete_downstream
    s = RseDeleteDownstream.new
    s.t2 <+ [[5, 10], [6, 11]]
    s.t3 <+ [[5, 10]]
    2.times { s.tick }

    assert_equal([[6, 11]], s.t2.to_a.sort)
  end

  def test_rse_negate_scratch_lhs
    s = RseNegateScratchLhs.new
    s.t1 <+ [[5, 10], [6, 11]]
    s.t2 <+ [[6, 11]]
    s.t3 <+ [[6, 11]]
    2.times { s.tick }

    assert_equal([[5, 10]], s.t1.to_a.sort)
  end

  def test_rse_negate_scratch_lhs_bad
    s = RseNegateScratchLhsBad.new
    s.t1 <+ [[5, 10], [6, 11]]
    s.t2 <+ [[6, 11]]
    2.times { s.tick }

    assert_equal([[5, 10], [6, 11]], s.t1.to_a.sort)
  end

  def test_rse_negate_scratch_lhs_bad2
    s = RseNegateScratchLhsBad2.new
    s.t1 <+ [[5, 10], [6, 11]]
    s.t2 <+ [[6, 11]]
    s.t3 <+ [[6, 11]]
    2.times do
      s.r3 <+ [[6, 11]]
      s.tick
    end

    assert_equal([[5, 10], [6, 11]], s.t1.to_a.sort)
  end

  def test_rse_negate_scratch_lhs_bad3
    s = RseNegateScratchLhsBad3.new
    s.t1 <+ [[5, 10], [6, 11]]
    s.t2 <+ [[6, 11]]
    2.times { s.tick }

    assert_equal([[5, 10], [6, 11]], s.t1.to_a.sort)
  end

  def test_rse_rhs_ref
    s = RseRhsRef.new
    s.t1 <+ [[1, 1], [2, 2]]
    s.t2 <+ [[2, 2], [3, 3]]
    2.times { s.tick }

    assert_equal([[1, 1]], s.t1.to_a.sort)
  end

  def test_rse_rhs_ref_bad
    s = RseRhsRefBad.new
    s.t1 <+ [[1, 1], [2, 2]]
    s.t2 <+ [[2, 2], [3, 3]]
    s.t4 <+ [[1, 1], [2, 2]]
    s.t5 <+ [[2, 2], [3, 3]]
    s.t7 <+ [[1, 1], [2, 2]]
    s.t8 <+ [[2, 2], [3, 3]]
    s.t11 <+ [[1, 1], [2, 2]]
    s.t12 <+ [[2, 2], [3, 3]]
    2.times { s.tick }

    assert_equal([[1, 1], [2, 2]], s.t1.to_a.sort)
    assert_equal([[1, 1], [2, 2]], s.t4.to_a.sort)
    assert_equal([[1, 1], [2, 2]], s.t7.to_a.sort)
    assert_equal([[1, 1], [2, 2]], s.t11.to_a.sort)
  end

  def test_join_rse
    j = JoinRse.new
    j.node <+ [["foo", 1], ["bar", 1], ["bar", 2]]
    j.sbuf <+ [[100, 1, "x"], [101, 1, "y"]]
    2.times { j.tick }
    assert_equal([[100, 1, "x"], [101, 1, "y"]], j.sbuf.to_a.sort)
    assert_equal([["bar", 1], ["bar", 2], ["foo", 1]], j.node.to_a.sort)

    j.res_approx <+ [["foo", 100, 1, "x"], ["foo", 101, 1, "y"]]
    2.times { j.tick }
    assert_equal([[100, 1, "x"], [101, 1, "y"]], j.sbuf.to_a.sort)
    assert_equal([["bar", 1], ["bar", 2], ["foo", 1]], j.node.to_a.sort)

    # No more messages in epoch 1
    j.seal_sbuf_epoch <+ [[1]]
    2.times { j.tick }
    assert_equal([[100, 1, "x"], [101, 1, "y"]], j.sbuf.to_a.sort)
    assert_equal([["bar", 1], ["bar", 2]], j.node.to_a.sort)

    # No more node addresses in epoch 1
    j.seal_node_epoch <+ [[1]]
    2.times { j.tick }
    assert_equal([[100, 1, "x"], [101, 1, "y"]], j.sbuf.to_a.sort)
    assert_equal([["bar", 1], ["bar", 2]], j.node.to_a.sort)

    j.res_approx <+ [["bar", 100, 1, "x"]]
    2.times { j.tick }
    assert_equal([[101, 1, "y"]], j.sbuf.to_a.sort)
    assert_equal([["bar", 1], ["bar", 2]], j.node.to_a.sort)

    j.res_approx <+ [["bar", 101, 1, "y"]]
    2.times { j.tick }
    assert_equal([], j.sbuf.to_a.sort)
    assert_equal([["bar", 2]], j.node.to_a.sort)
  end

  def test_join_rse_variant_qual
    j = JoinRseVariantQuals.new
    j.node <+ [["foo", 1], ["bar", 1], ["bar", 2]]
    j.sbuf <+ [[100, 1, "x"], [101, 1, "y"]]
    2.times { j.tick }
    assert_equal([[100, 1, "x"], [101, 1, "y"]], j.sbuf.to_a.sort)
    assert_equal([["bar", 1], ["bar", 2], ["foo", 1]], j.node.to_a.sort)

    j.res_approx <+ [["foo", 100, 1, "x"], ["foo", 101, 1, "y"]]
    2.times { j.tick }
    assert_equal([[100, 1, "x"], [101, 1, "y"]], j.sbuf.to_a.sort)
    assert_equal([["bar", 1], ["bar", 2], ["foo", 1]], j.node.to_a.sort)

    # No more messages in epoch 1
    j.seal_sbuf_epoch <+ [[1]]
    2.times { j.tick }
    assert_equal([[100, 1, "x"], [101, 1, "y"]], j.sbuf.to_a.sort)
    assert_equal([["bar", 1], ["bar", 2]], j.node.to_a.sort)

    # No more node addresses in epoch 1
    j.seal_node_epoch <+ [[1]]
    2.times { j.tick }
    assert_equal([[100, 1, "x"], [101, 1, "y"]], j.sbuf.to_a.sort)
    assert_equal([["bar", 1], ["bar", 2]], j.node.to_a.sort)

    j.res_approx <+ [["bar", 100, 1, "x"]]
    2.times { j.tick }
    assert_equal([[101, 1, "y"]], j.sbuf.to_a.sort)
    assert_equal([["bar", 1], ["bar", 2]], j.node.to_a.sort)

    j.res_approx <+ [["bar", 101, 1, "y"]]
    2.times { j.tick }
    assert_equal([], j.sbuf.to_a.sort)
    assert_equal([["bar", 2]], j.node.to_a.sort)
  end

  def test_join_rse_no_qual
    j = JoinRseNoQual.new
    j.node <+ [["foo"], ["bar"]]
    j.sbuf <+ [[1, "x"], [2, "y"], [3, "z"]]
    2.times { j. tick }
    assert_equal([["bar"], ["foo"]], j.node.to_a.sort)
    assert_equal([[1, "x"], [2, "y"], [3, "z"]], j.sbuf.to_a.sort)

    j.seal_node <+ [["..."]]
    2.times { j. tick }
    assert_equal([["bar"], ["foo"]], j.node.to_a.sort)
    assert_equal([[1, "x"], [2, "y"], [3, "z"]], j.sbuf.to_a.sort)

    j.res_approx <+ [[1, "x", "foo"], [2, "y", "bar"],
                     [3, "z", "foo"], [3, "z", "bar"]]
    2.times { j. tick }
    assert_equal([["bar"], ["foo"]], j.node.to_a.sort)
    assert_equal([[1, "x"], [2, "y"]], j.sbuf.to_a.sort)

    j.res_approx <+ [[2, "y", "foo"]]
    2.times { j. tick }
    assert_equal([["bar"], ["foo"]], j.node.to_a.sort)
    assert_equal([[1, "x"]], j.sbuf.to_a.sort)

    j.seal_sbuf <+ [["..."]]
    2.times { j. tick }
    assert_equal([["bar"]], j.node.to_a.sort)
    assert_equal([[1, "x"]], j.sbuf.to_a.sort)

    j.res_approx <+ [[1, "x", "bar"]]
    2.times { j. tick }
    assert_equal([], j.node.to_a.sort)
    assert_equal([], j.sbuf.to_a.sort)
  end

  # Sealed collections don't need an explicit seal
  def test_join_rse_sealed
    j = JoinRseSealed.new
    j.sbuf <+ [[1, "a"], [2, "b"], [3, "c"]]
    2.times { j.tick }
    assert_equal([[1, "a"], [2, "b"], [3, "c"]], j.sbuf.to_a.sort)

    j.res_approx <+ [[1, "a", "bar"], [1, "a", "foo"], [2, "b", "bar"]]
    2.times { j.tick }
    assert_equal([[2, "b"], [3, "c"]], j.sbuf.to_a.sort)
  end

  def test_join_rse_negation_qual
    j = JoinRseNegationQual.new
    j.sbuf <+ [[1, "a"], [2, "b"], [3, "c"]]
    2.times { j.tick }
    assert_equal([[1, "a"], [2, "b"], [3, "c"]], j.sbuf.to_a.sort)

    j.res_approx <+ [["bar", 1, "x"], ["foo", 1, "x"], ["bar", 2, "x"]]
    2.times { j.tick }
    assert_equal([[2, "b"], [3, "c"]], j.sbuf.to_a.sort)
  end

  def test_join_rse_negation_qual_variant
    j = JoinRseNegationQualVariant.new
    j.sbuf <+ [[1, "a"], [2, "b"], [3, "c"]]
    2.times { j.tick }
    assert_equal([[1, "a"], [2, "b"], [3, "c"]], j.sbuf.to_a.sort)

    j.res_approx <+ [["x", "bar", 1], ["y", "foo", 1], ["z", "bar", 2]]
    2.times { j.tick }
    assert_equal([[3, "c"]], j.sbuf.to_a.sort)
  end

  def test_rse_join_sealed_twice
    j = JoinRseSealedUseTwice.new
    j.tick
  end

  def test_rse_join_twice
    j = JoinRseUseTwice.new
    j.tick
  end

  def test_rse_join_twice_reclaim_from_sealed
    j = JoinRseSealDoubleReclaim.new
    j.node <+ [["foo", "a", 1], ["bar", "a", 1],
               ["foo", "b", 1], ["bar", "c", 2]]
    j.tick

    j.x_log <+ [[100, "a"], [101, "b"]]
    j.tick

    assert_equal([["foo", "a", 1, 100, "a"],
                  ["foo", "b", 1, 101, "b"],
                  ["bar", "a", 1, 100, "a"]].sort,
                 j.x_res.to_a.sort)

    j.x_res_approx <+ [["foo", "a", 1, 100, "a"],
                       ["foo", "b", 1, 101, "b"]]
    2.times { j.tick }

    # x_log message 101 has been delivered to all the nodes in x_epoch "b" (just
    # "foo"); x_log message 100 hasn't been delivered to "bar" in x_epoch "a".
    assert_equal([[100, "a"]], j.x_log.to_a.sort)

    # There will be no more x_log messages in x_epoch "b" -- BUT, since there
    # might still be y_log messages in y_epoch 1, we can't GC the node fact for
    # x_epoch "b".
    j.seal_x_log_epoch <+ [["b"]]
    2.times { j.tick }

    assert_equal([["foo", "a", 1], ["bar", "a", 1],
                  ["foo", "b", 1], ["bar", "c", 2]].sort, j.node.to_a.sort)
  end

  def test_rse_join_double_scratch
    j = JoinRseDoubleScratch.new
    j.obj <+ [[5, "foo"], [10, "bar"]]
    j.ref <+ [[1, "x", 5], [2, "y", 5], [3, "z", 10]]
    2.times { j.tick }

    assert_equal([[5, "foo"], [10, "bar"]].to_set, j.obj.to_set)
    assert_equal([[1, "x", 5], [2, "y", 5], [3, "z", 10]].to_set, j.ref.to_set)

    j.seal_ref <+ [[true]]
    j.seal_obj <+ [[true]]      # XXX: Shouldn't be necessary
    j.del_ref <+ [[100, 1], [101, 2]]
    2.times { j.tick }

    assert_equal([[10, "bar"]].to_set, j.obj.to_set)
    assert_equal([[3, "z", 10]].to_set, j.ref.to_set)
  end

  def test_rse_join_tlist_const
    j = JoinRseTlistConst.new
    j.b <+ [[5, 10], [6, 11]]
    j.c <+ [[7, 12]]
    j.a_approx <+ [[5, "foo", 12], [6, 99, 12]]
    2.times { j.tick }

    assert_equal([[5, 99, 12], [6, "foo", 12]].to_set, j.a.to_set)
    assert_equal([[5, 10], [6, 11]], j.b.to_a.sort)

    j.a_approx <+ [[5, 99, 12]]
    2.times { j.tick }

    assert_equal([[6, 11]], j.b.to_a.sort)
  end

  def test_rse_join_tlist_ip_port
    j = JoinRseTlistIpPort.new(:ip => "localhost", :port => 5555)
    j.b <+ [[5, 10], [6, 11]]
    j.c <+ [[7, 12]]
    j.a_approx <+ [[5, j.ip_port, j.port, 12]]
    2.times { j.tick }

    assert_equal([[6, j.ip_port, j.port, 12]].to_set, j.a.to_set)
    assert_equal([[6, 11]].to_set, j.b.to_set)
  end

  def test_rse_join_tlist_const_qual
    j = JoinRseTlistConstQual.new(:ip => "localhost", :port => 5556)
    j.b <+ [[5, 10], [6, 11]]
    j.c <+ [[7, 12]]
    j.a_approx <+ [[5, j.port, 100], [6, j.port + 1, 12]]
    2.times { j.tick }

    assert_equal([[6, j.port, 12]].to_set, j.a.to_set)
    assert_equal([[6, 11]].to_set, j.b.to_set)
  end
end

class SealedCollection
  include Bud

  state do
    sealed :foo, [:x] => [:y]
    table :baz, foo.schema
  end

  bootstrap do
    foo <= [[5, 10], [6, 12]]
  end

  bloom do
    baz <= foo
  end
end

class TestSealed < MiniTest::Unit::TestCase
  def test_simple
    i = SealedCollection.new
    i.tick
    assert_equal([[5, 10], [6, 12]], i.foo.to_a.sort)
    assert_equal([[5, 10], [6, 12]], i.baz.to_a.sort)

    assert_raises(Bud::CompileError) do
      i.foo <+ [[7, 15]]
    end
  end
end
