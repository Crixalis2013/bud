# gratuitous tests to ensure code coverage
require 'test_common'

class Nada
  include Bud

  state do
    table :num, [:num]
  end

  bloom do
    num <= (1..5).map{|i| [i]}
  end
end

# lib/bud.rb
class GratuitousBud < Test::Unit::TestCase
  def test_sigint
    pid = fork do 
      p = Nada.new
      p.run
    end
    sleep(1)
    Process.kill("INT", pid)
    Process.wait
  end
  def test_sigtrap
    pid = fork do 
      p = Nada.new
      p.run
    end
    sleep(1)
    Process.kill("TRAP", pid)
    Process.wait
  end
end
