# simple word count
require 'test_common'
require 'backports'

class WordCount1
  include Bud

  attr_reader :pattern

  def initialize(pattern)
    super()
    @pattern = pattern
  end

  state do
    file_reader :txt, 'text/ulysses.txt'
    # file_reader :txt, 'shaks12.txt'
    scratch :wc, [:word] => [:cnt]
  end

  bloom do
    wc <= txt.flat_map do |t|
            t.text.split.enum_for(:each_with_index).map {|w, i| [t.lineno, i, w]}
          end.rename(:loo, [:lineno, :wordno, :word]).group([:word], count)
  end
end

class TestWC1 < Test::Unit::TestCase
  def test_wc1
    program = WordCount1.new(/[Bb]loom/)
    assert_nothing_raised { program.tick }
    assert_equal(23, program.wc[["yes"]].cnt)
  end
end


class WordCount2
  include Bud

  attr_reader :pattern

  def initialize(pattern)
    super()
    @pattern = pattern
  end

  state do
    file_reader :txt, 'text/ulysses.txt'
    scratch :words, [:lineno, :wordno] => [:word]
    scratch :wc, [:word] => [:cnt]
  end

  bloom do
    words <= txt.flat_map do |t|
      t.text.split.enum_for(:each_with_index).map {|w, i| [t.lineno, i, w]}
    end
    wc <= words.reduce({}) do |memo, t|
      memo[t.word] ||= 0
      memo[t.word] += 1
      memo
    end
  end
end

class TestWC2 < Test::Unit::TestCase
  def test_wc2
    program = WordCount2.new(/[Bb]loom/)
    assert_nothing_raised { program.tick }
    assert_equal(23, program.wc[["yes"]].cnt)
  end
end