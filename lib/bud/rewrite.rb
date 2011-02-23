require 'rubygems'
require 'ruby2ruby'

class RW < Ruby2Ruby
  attr_accessor :rule_indx, :rules, :depends

  def initialize(seed)
    @ops = {:<< => 1, :< => 1, :<= => 1}
    @nm_funcs = {:group => 1, :argagg => 1, :include? => 1, :-@ => 1}
    @temp_ops = {:-@ => 1, :~ => 1, :+@ => 1}
    @tabs = {}
    # for upstream compatibility.  consider using a bool
    @nm = 0
    @rule_indx = seed
    @collect = false
    @delete = false
    @join_alias = {}
    @rules = []
    @depends = []
    super()
  end

  def process_lasgn(exp)
    if exp.length == 2
      do_join_alias(exp)
    else
      super
    end
  end

  def process_lvar(exp)
    lvar = exp[0].to_s
    if @join_alias[lvar]
      @tabs[lvar] = @nm
      drain(exp)
      return lvar
    else
      super
    end
  end

  def process_call(exp)
    if exp[0].nil? and exp[2] == s(:arglist) and @collect
      do_tab(exp)
    elsif @ops[exp[1]] and self.context[1] == :block
      do_rule(exp)
    else
      # basically not analyzed
      if @nm_funcs[exp[1]]
        @nm = 1
      end
      if @temp_ops[exp[1]]
        @temp_op = exp[1].to_s.gsub("@", "")
      end
      super
    end
  end

  def collect_rhs(exp)
    @collect = true
    rhs = process exp
    @collect = false
    return rhs
  end

  def record_rule(lhs, op, rhs)
    rule_txt = "#{lhs} #{op} #{rhs}"
    if op == :<
      op = "<#{@temp_op}"
    else
      op = op.to_s
    end

    @rules << [@rule_indx, lhs, op, rule_txt]
    @tabs.each_pair do |k, v|
      @depends << [@rule_indx, lhs, op, k, v]
    end

    @tabs = {}
    @nm = 0
    @temp_op = nil
    @rule_indx += 1
  end

  def do_tab(exp)
    tab = exp[1].to_s
    @tabs[tab] = @nm
    drain(exp)
    return tab
  end

  def do_join_alias(exp)
    tab = exp[0].to_s
    @join_alias[tab] = true
    @tabs[tab] = @nm
    @collect = true
    rhs = collect_rhs(exp[1])
    @collect = false
    record_rule(tab, "=", rhs)
    drain(exp)
  end

  def do_rule(exp)
    lhs = process exp[0]
    op = exp[1]
    rhs = collect_rhs(exp[2])
    record_rule(lhs, op, rhs)
    drain(exp)
  end

  def each
    @flat_state.each {|f| yield f}
  end

  def drain(exp)
    exp.shift until exp.empty?
    return ""
  end
end


class StateExtractor < Ruby2Ruby
  attr_reader :tabs, :decls

  def initialize(context)
    @cxt = context
    @tabs = {}
    @ttype = nil
    @decls = []
    super()
  end

  def process_call(exp)
    lhs = process exp[2]
    foo = "#{exp[1]} #{lhs}"
    @decls << ["#{lhs}"[/:.*?,/][1..-1].chop!, foo]
    exp.shift while exp.length > 0
    return ""
  end
end
