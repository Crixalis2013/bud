require 'test_common'

module ParentModule
  include BudModule

  state do
    table :boot_t
  end

  bootstrap do
    boot_t << [5, 10]
    boot_t << [20, 30]
  end
end

class ImportParent
  include Bud
  import ParentModule => :p
  import ParentModule => :q

  state do
    table :t2
    table :t3
  end

  declare
  def rules
    t2 <= p.boot_t.map {|t| [t.key + 1, t.val + 1]}
    t3 <= q.boot_t.map {|t| [t.key + 1, t.val + 1]}
  end
end

module ChildModule
  include BudModule
  import ParentModule => :p

  state do
    table :t1
  end
end

class ImportGrandParent
  include Bud
  import ChildModule => :c
  import ParentModule => :p

  state do
    table :t2
    table :t3
  end

  declare
  def rules
    t2 <= c.p.boot_t
    t3 <= p.boot_t.map {|p| [p.key + 10, p.val + 20]}
  end
end

class TestModules < Test::Unit::TestCase
  def test_simple_bootstrap
    c = ImportParent.new
    c.tick
    assert_equal([[6, 11], [21, 31]], c.t2.to_a.sort)
    assert_equal(c.t2.to_a.sort, c.t2.to_a.sort)
  end

  def test_nested_import
    c = ImportGrandParent.new
    c.tick
    assert_equal([[5, 10], [20, 30]], c.t2.to_a.sort)
    assert_equal([[15, 30], [30, 50]], c.t3.to_a.sort)
  end
end
