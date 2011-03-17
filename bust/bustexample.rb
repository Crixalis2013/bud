require 'rubygems'
require 'bud'
require 'bust'

class BustExample
  include Bud
  include Bust

  state do
    table :foo, [:bar, :baz, :qux]
  end

  bloom do
    stdio <~ foo.map {|t| [t.inspect]}
  end
end

BustExample.new.run
