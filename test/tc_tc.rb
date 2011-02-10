require 'rubygems'
require 'bud'
require 'test/unit'
require 'fileutils'

class TcTest < Bud
  def state
    tctable :t1, ['k1', 'k2'], ['v1', 'v2']
    table :in_buf, ['k1', 'k2', 'v1', 'v2']
    table :del_buf, ['k1', 'k2', 'v1', 'v2']
    table :pending_buf, ['k1', 'k2'], ['v1', 'v2']
    table :pending_buf2, ['k1', 'k2'], ['v1', 'v2']

    scratch :t2, ['k'], ['v']
    scratch :t3, ['k'], ['v']
    scratch :t4, ['k'], ['v']
    tctable :chain_start, ['k'], ['v']
    tctable :chain_del, ['k'], ['v']

    tctable :join_t1, ['k'], ['v1', 'v2']
    tctable :join_t2, ['k'], ['v1', 'v2']
    scratch :cart_prod, ['k', 'v1', 'v2']
    scratch :join_res, ['k'], ['v1', 'v2']
  end

  declare
  def logic
    t1 <= in_buf
    t1 <- del_buf
    t1 <+ pending_buf
    t1 <+ pending_buf2
  end

  declare
  def do_chain
    t2 <= chain_start.map{|c| [c.k, c.v + 1]}
    t3 <= t2.map{|c| [c.k, c.v + 1]}
    t4 <= t3.map{|c| [c.k, c.v + 1]}
    chain_start <- chain_del
  end

  declare
  def do_join
    j = join [join_t1, join_t2], [join_t1.k, join_t2.k]
    join_res <= j
    cart_prod <= join([join_t1, join_t2])
  end
end

class TestTc < Test::Unit::TestCase
  BUD_DIR = "#{Dir.pwd}/bud_tmp"

  def setup
    rm_bud_dir
    @t = make_bud(true)
  end

  def teardown
    unless @t.nil?
      @t.close_tables
      @t = nil
    end
    rm_bud_dir
  end

  def make_bud(truncate)
    TcTest.new(:tc_dir => BUD_DIR, :tc_truncate => truncate, :quiet => true)
  end

  def rm_bud_dir
    return unless File.directory? BUD_DIR
    FileUtils.rm_r(BUD_DIR)
  end

  def test_basic_ins
    assert_equal(0, @t.t1.length)
    @t.in_buf << ['1', '2', '3', '4']
    @t.in_buf << ['1', '3', '3', '4']
    assert_nothing_raised(RuntimeError) {@t.tick}
    assert_equal(2, @t.t1.length)
    assert(@t.t1.include? ['1', '2', '3', '4'])
    assert(@t.t1.has_key? ['1', '2'])
    assert_equal(false, @t.t1.include?(['1', '2', '3', '5']))
  end

  def test_key_conflict_delta
    @t.in_buf << ['1', '2', '3', '4']
    @t.in_buf << ['1', '2', '3', '5']
    assert_raise(Bud::KeyConstraintError) {@t.tick}
  end

  def test_key_conflict
    @t.in_buf << ['1', '2', '3', '4']
    assert_nothing_raised(RuntimeError) {@t.tick}
    @t.in_buf << ['1', '2', '3', '5']
    assert_raise(Bud::KeyConstraintError) {@t.tick}
  end

  def test_key_merge
    @t.in_buf << ['1', '2', '3', '4']
    @t.in_buf << ['1', '2', '3', '4']
    @t.in_buf << ['1', '2', '3', '4']
    @t.in_buf << ['1', '2', '3', '4']
    @t.in_buf << ['5', '10', '3', '4']
    @t.in_buf << ['6', '10', '3', '4']
    @t.in_buf << ['6', '10', '3', '4']

    @t.t1 << ['1', '2', '3', '4']
    @t.t1 << ['1', '2', '3', '4']

    assert_nothing_raised(RuntimeError) {@t.tick}
    assert_equal(3, @t.t1.length)
  end

  def test_persist
    @t.in_buf << [1, 2, 3, 4]
    @t.in_buf << [5, 10, 3, 4]
    assert_nothing_raised(RuntimeError) {@t.tick}
    assert_equal(2, @t.t1.length)

    10.times do |i|
      @t.close_tables
      @t = make_bud(false)
      @t.in_buf << [6, 10 + i, 3, 4]
      assert_nothing_raised(RuntimeError) {@t.tick}
      assert_equal(3 + i, @t.t1.length)
    end
  end

  def test_pending_ins
    @t.pending_buf << ['1', '2', '3', '4']
    assert_nothing_raised(RuntimeError) {@t.tick}
    assert_equal(0, @t.t1.length)
    assert_nothing_raised(RuntimeError) {@t.tick}
    assert_equal(1, @t.t1.length)
  end

  def test_pending_key_conflict
    @t.pending_buf << ['1', '2', '3', '4']
    @t.pending_buf2 << ['1', '2', '3', '5']
    assert_raise(Bud::KeyConstraintError) {@t.tick}
  end

  def test_basic_del
    @t.t1 << ['1', '2', '3', '4']
    @t.t1 << ['1', '3', '3', '4']
    @t.t1 << ['2', '4', '3', '4']
    assert_nothing_raised(RuntimeError) {@t.tick}
    assert_equal(3, @t.t1.length)

    @t.del_buf << ['2', '4', '3', '4'] # should delete
    assert_nothing_raised(RuntimeError) {@t.tick}
    assert_equal(3, @t.t1.length)
    assert_nothing_raised(RuntimeError) {@t.tick}
    assert_equal(2, @t.t1.length)

    @t.del_buf << ['1', '3', '3', '5'] # shouldn't delete
    assert_nothing_raised(RuntimeError) {@t.tick}
    assert_equal(2, @t.t1.length)
    assert_nothing_raised(RuntimeError) {@t.tick}
    assert_equal(2, @t.t1.length)

    @t.del_buf << ['1', '3', '3', '4'] # should delete
    assert_nothing_raised(RuntimeError) {@t.tick}
    assert_equal(2, @t.t1.length)
    assert_nothing_raised(RuntimeError) {@t.tick}
    assert_equal(1, @t.t1.length)
  end

  def test_chain
    @t.chain_start << [5, 10]
    @t.chain_start << [10, 15]
    assert_nothing_raised(RuntimeError) {@t.tick}
    assert_equal(2, @t.t2.length)
    assert_equal(2, @t.t3.length)
    assert_equal(2, @t.t4.length)
    assert_equal([10,18], @t.t4[[10]])

    @t.chain_del << [5,10]
    assert_nothing_raised(RuntimeError) {@t.tick}
    assert_equal(2, @t.chain_start.length)
    assert_equal(2, @t.t2.length)
    assert_equal(2, @t.t3.length)
    assert_equal(2, @t.t4.length)
    assert_nothing_raised(RuntimeError) {@t.tick}
    assert_equal(1, @t.chain_start.length)
    assert_equal(1, @t.t2.length)
    assert_equal(1, @t.t3.length)
    assert_equal(1, @t.t4.length)
  end

  def test_cartesian_product
    @t.join_t1 << [12, 50, 100]
    @t.join_t1 << [15, 50, 120]
    @t.join_t2 << [12, 70, 150]
    @t.join_t2 << [6, 20, 30]

    assert_nothing_raised(RuntimeError) {@t.tick}
    assert_equal(4, @t.cart_prod.length)

    @t.join_t2 << [6, 20, 30] # dup
    @t.join_t2 << [18, 70, 150]

    assert_nothing_raised(RuntimeError) {@t.tick}
    assert_equal(6, @t.cart_prod.length)
  end

  def test_join
    @t.join_t1 << [12, 50, 100]
    @t.join_t1 << [15, 50, 120]
    @t.join_t2 << [12, 70, 150]
    @t.join_t2 << [6, 20, 30]
    assert_nothing_raised(RuntimeError) {@t.tick}

    assert_equal(1, @t.join_res.length)
  end
end
