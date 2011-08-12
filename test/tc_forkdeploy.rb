require 'test_common'
require 'stringio'
require '../examples/deploy/tokenring'
require 'timeout'

NUM_DEPLOY_FORKS = 10

class RingFork
  include Bud
  include TokenRing
  include ForkDeploy

  deploystrap do
    node_count << [NUM_DEPLOY_FORKS]
  end

  bloom :pass_token_once do
    next_node <- (next_node * token_persist).lefts
  end
end

class TestForkDeploy < Test::Unit::TestCase
  def test_fork_deploy
    deploy_out = StringIO.new
    begin
      $stdout = deploy_out
      do_fork_test
    ensure
      $stdout = STDOUT
    end
  end

  def do_fork_test
    read, write = IO.pipe
    child_opts = { :stdout => write }
    ring_fork = RingFork.new(:deploy => true, :stdout => write,
                             :deploy_child_opts => child_opts)
    ring_fork.run_bg

    lines = []
    Timeout::timeout(45) do
      ((NUM_DEPLOY_FORKS * 2) + 1).times do
        lines << read.readline
      end
    end

    ring_fork.stop_bg

    # We can close pipe now that ring_fork is stopped
    read.close
    write.close


    # Assert there are no child processes left; we've closed them all
    assert_equal([], Process.waitall)

    # Console output from different nodes might be intermixed in output pipe
    # (i.e., "lines" might not respect token delivery order). We just check that
    # each node got the token the same number of times. We also check for and
    # skip "child node ready" status indicators.
    node_output = []
    node_ready = {}
    lines.each do |l|
      m = l.match "Child node ready: (\\d+)"
      if m
        node_id = m[1].to_i
        assert_equal(false, node_ready.has_key?(node_id))
        node_ready[node_id] = true
        next
      end

      m = l.match "^(\\d+): Got token!"
      assert(m)
      node_id = m[1].to_i
      node_output[node_id] ||= 0
      node_output[node_id] += 1
    end

    assert_equal(NUM_DEPLOY_FORKS, node_ready.size)
    assert_equal(NUM_DEPLOY_FORKS, node_output.size)
    node_output.each_with_index do |n,i|
      if i == 0
        assert_equal(2, n)
      else
        assert_equal(1, n)
      end
    end
  end
end
