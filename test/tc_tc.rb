require 'rubygems'
require 'bud'
require 'test/unit'

class TcTest < Bud
  def state
    tctable :t1, ['k1', 'k2'], ['v1', 'v2']
    table :in_buf, ['k1', 'k2', 'v1', 'v2']
  end

  declare
  def logic
    t1 <= in_buf
  end
end

class TestTc < Test::Unit::TestCase
  def test_basic_ins
    t = TcTest.new('localhost', 12345)
    t.in_buf << ['1', '2', '3', '4']
    t.in_buf << ['1', '3', '3', '4']
    assert_nothing_raised(RuntimeError) {t.tick}
    assert_equal(2, t.t1.length)
  end

  def test_key_conflict
    t = TcTest.new('localhost', 12346)
    t.in_buf << ['1', '2', '3', '4']
    t.in_buf << ['1', '2', '3', '5']
    assert_raise(Bud::KeyConstraintError) {t.tick}
  end

  def test_key_merge
    t = TcTest.new('localhost', 12347)
    t.in_buf << ['1', '2', '3', '4']
    t.in_buf << ['1', '2', '3', '4']
    t.in_buf << ['1', '2', '3', '4']
    t.in_buf << ['1', '2', '3', '4']
    t.in_buf << ['5', '10', '3', '4']
    t.in_buf << ['6', '10', '3', '4']
    assert_nothing_raised(RuntimeError) {t.tick}
    assert_equal(3, t.t1.length)
  end
end
