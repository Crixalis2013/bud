require 'test_common'
require 'stringio'
require '../examples/deploy/tokenring'
require 'bud/deploy/localdeploy'
require 'timeout'

DEPLOY_NUM_NODES = 10

class RingLocal
  include Bud
  include TokenRing
  include LocalDeploy

  deploystrap do
    node_count << [DEPLOY_NUM_NODES]
  end

  bloom :pass_token_once do
    next_node <- (next_node * token_persist).lefts {|n| n.node}
  end
end

class TestLocalDeploy < Test::Unit::TestCase
  def test_local_deploy
    read, write = IO.pipe
    $stdout = write
    ring_local = RingLocal.new(:deploy => true)
    ring_local.run_bg

    lines = []
    begin
      Timeout::timeout(60) do
        (DEPLOY_NUM_NODES + 3).times do
          lines << read.readline
        end
      end
    ensure
      $stdout = STDOUT
    end
    # Close pipe
    read.close
    write.close

    # Take off the "deploying....done" stuff
    lines = lines[1..-1]

    # Token starts and ends up at the same place
    assert_equal(lines[0], lines[-1])

    # Token circulates amongst nodes
    for i in (1..lines.size-1)
      assert(lines[i]["Got token!"])
      for j in (i+1..lines.size-1)
        assert_not_equal(lines[i], lines[j])
      end
    end

    begin
      $stdout = StringIO.new
      ring_local.stop_bg
      # Assert there are no child processes left; we've closed them all
      assert_equal(Process.waitall, [])
    ensure
      $stdout = STDOUT
    end
  end
end
