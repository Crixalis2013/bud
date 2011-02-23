require 'rubygems'
require 'bud'
require 'deployer'
require 'localdeploy'

class Quicksort
  include Bud
  include Deployer
  include LocalDeploy

  state {
    channel :elt_list, [:@loc] => [:elt_list]
    channel :succ, [:@loc, :elt1, :elt2]
    table :master, [] => [:node]
    table :child, [] => [:node]
    scratch :pivot, [] => [:elt]
    scratch :geq_pivot, [] => [:list]
    scratch :lt_pivot, [] => [:list]
    scratch :list_to_sort, [] => [:list]
    table :input_list, [] => [:list] # the "input"
  }

  bootstrap do
    input_list << [[6,3,8,2,7,9,1,5,4,0]]
    node_count <= [[input_list[[]].list.size]]
  end

  declare
  def partition
    initial_data <= ((if node.size == node_count[[]].num
                        node.map do |n|
                          # send the first node the entire list
                          if n.uid == 1
                            [n.uid,
                             [[:master, [[me]]],
                              [:child, [[node[[n.uid+1]].node]]],
                              [:list_to_sort, [[input_list[[]].list]]]]
                            ]
                          # don't send the last node a child
                          elsif n.uid == node_count[[]].num
                            [n.uid,
                             [[:master, [[me]]]]
                            ]
                          else
                            [n.uid,
                             [[:master, [[me]]],
                              [:child, [[node[[n.uid+1]].node]]]]
                            ]
                          end
                        end
                      end) or [])
  end

  declare
  def quicksort
    # pop elt_list into list_to_sort
    stdio <~ list_to_sort.map {|l| ["Received list: " + l.inspect]}
    list_to_sort <= [elt_list.map {|e| e.elt_list}]

    # pick a pivot (first element in the list)
    # XXX: should switch to the median to be better
    pivot <= ((list_to_sort[[]] and [[list_to_sort[[]].list[0]]]) or [])
    geq_pivot <= ((pivot[[]] and list_to_sort[[]] and
                   [[list_to_sort[[]].list[1..-1].find_all do |e|
                       e >= pivot[[]].elt
                     end]]) or [])
    lt_pivot <= ((pivot[[]] and list_to_sort[[]] and
                  [[list_to_sort[[]].list[1..-1].find_all do |e|
                      e < pivot[[]].elt
                    end]]) or [])

    # elements >= pivot are kept local
    elt_list <~ ((geq_pivot[[]] and not geq_pivot[[]].list.empty? and
                  [[me, geq_pivot[[]].list]]) or [])
    # elements < pivot are sent away (w/ random delay for fun)
    elt_list <~ ((lt_pivot[[]] and not lt_pivot[[]].list.empty? and
                  child[[]] and sleep(rand) and
                  [[child[[]].node, lt_pivot[[]].list]]) or [])

    # send the first link we know to the master
    succ <~ ((master[[]] and lt_pivot[[]] and not lt_pivot[[]].list.empty? and
              [[master[[]].node, lt_pivot[[]].list.max, pivot[[]].elt]]) or [])

    # send the second link we know to the master
    succ <~ ((master[[]] and geq_pivot[[]] and not geq_pivot[[]].list.empty? and
              [[master[[]].node, pivot[[]].elt, geq_pivot[[]].list.min]]) or [])

    # print out links as we get them
    stdio <~ succ.map do |s|
      ["Successor: (" + s.elt1.to_s + ", " + s.elt2.to_s + ")"]
    end
  end

end

program = Quicksort.new(:scoping => true, :ip => "127.0.0.1", :port => 0)
program.run
