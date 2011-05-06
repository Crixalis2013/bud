require 'rubygems'
require 'bud'

module TokenRing
  state do
    table :next_node, [] => [:addr]
    channel :token, [:@loc]
    table :token_persist, [:loc]
  end

  bloom :make_ring do
    initial_data <= node do |n|
      # Calculate the successor node
      succ_id = (n.uid + 1) % node_count[[]].num
      succ_node = [node[[succ_id]].addr]
      [ n.uid, :next_node, [succ_node] ]
    end

    # The deployer sends an initial message to the node with ID 0
    token <~ node do |n|
      [n.addr] if (@options[:deploy] and n.uid == 0)
    end
  end

  bloom :pass_token do
    # Persist the token for as long as necessary
    token_persist <= token
    token_persist <- (token_persist * next_node).lefts
    # Pass on the token
    token <~ (token_persist * next_node).combos {[next_node[[]].addr]}
#    stdio <~ token {["#{ip_port}: Got token!"]}
  end
end
