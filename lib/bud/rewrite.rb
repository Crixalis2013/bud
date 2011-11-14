require 'rubygems'
require 'ruby2ruby'

class RuleRewriter < Ruby2Ruby # :nodoc: all
  attr_accessor :rule_indx, :rules, :depends

  def initialize(seed, bud_instance)
    @bud_instance = bud_instance
    @ops = {:<< => 1, :< => 1, :<= => 1}
    @monotonic_whitelist = {
          :== => 1, :+ => 1, :<= => 1, :- => 1, :< => 1, :> => 1,
          :* => 1, :pairs => 1, :matches => 1, :combos => 1, :flatten => 1,
          :lefts => 1, :rights => 1, :map => 1, :flat_map => 1, :pro => 1,
          :schema => 1, :keys => 1, :values => 1, :payloads => 1, :~ => 1
      }
    @temp_ops = {:-@ => 1, :~ => 1, :+@ => 1}
    @tables = {}
    @nm = false
    @rule_indx = seed
    @collect = false
    @rules = []
    @depends = []
    super()
  end

  def call_is_attr_deref?(recv, op)
    if recv.first == :call and @bud_instance.tables.has_key? recv[2]
      schema = @bud_instance.send(recv[2]).schema
      if schema and schema.include? op
        return true
      end
    end
    return false
  end

  def process_call(exp)
    recv, op, args = exp
    if recv.nil? and args == s(:arglist) and @collect
      do_table(exp)
    elsif @ops[op] and @context[1] == :block and @context.length == 4
      # NB: context.length is 4 when see a method call at the top-level of a
      # :defn block -- this is where we expect Bloom statements to appear
      do_rule(exp)
    else
      if recv and recv.class == Sexp
        # for CALM analysis, mark deletion rules as non-monotonic
        @nm = true if op == :-@
        # don't worry about monotone ops, table names, table.attr calls, or accessors of iterator variables
        unless @monotonic_whitelist[op] or @bud_instance.tables.has_key? op or call_is_attr_deref?(recv, op) or recv.first == :lvar
          @nm = true
        end
      end
      if @temp_ops[op]
        @temp_op = op.to_s.gsub("@", "")
      end
      super
    end
  end

  def collect_rhs(exp)
    @collect = true
    # rewrite constant array expressions to lambdas
    if exp[0] and exp[0] == :arglist 
      # the <= case
      if exp[1] and exp[1][0] == :array
        exp = s(exp[0], s(:iter, s(:call, nil, :lambda, s(:arglist)), nil, exp[1]))
      # the superator case
      elsif exp[1] and exp[1][0] == :call \
        and exp[1][1] and exp[1][1][0] and exp[1][1][0] == :array \
        and exp[1][2] and (exp[1][2] == :+@ or exp[1][2] == :-@)
        exp = s(exp[0], s(exp[1][0], s(:iter, s(:call, nil, :lambda, s(:arglist)), nil, exp[1][1]), exp[1][2], exp[1][3]))
      end
    end
    rhs = process exp
    @collect = false
    return rhs
  end

  def reset_instance_vars
    @tables = {}
    @nm = false
    @temp_op = nil
  end

  def record_rule(lhs, op, rhs_pos, rhs)
    rule_txt_orig = "#{lhs} #{op} (#{rhs})"
    rule_txt = "#{lhs} #{op} (#{rhs_pos})"
    if op == :<
      op = "<#{@temp_op}"
    else
      op = op.to_s
    end

    @rules << [@bud_instance, @rule_indx, lhs, op, rule_txt, rule_txt_orig]
    @tables.each_pair do |t, non_monotonic|
      @depends << [@bud_instance, @rule_indx, lhs, op, t, non_monotonic]
    end

    reset_instance_vars
    @rule_indx += 1
  end

  def do_table(exp)
    t = exp[1].to_s
    # If we're called on a "table-like" part of the AST that doesn't correspond
    # to an extant table, ignore it.
    @tables[t] = @nm if @bud_instance.tables.has_key? t.to_sym
    drain(exp)
    return t
  end

  def do_rule(exp)
    lhs = process exp[0]
    op = exp[1]
    pro_rules = map2pro(exp[2])
    if @bud_instance.options[:no_attr_rewrite]
      rhs = collect_rhs(pro_rules)
      rhs_pos = rhs
    else
      # need a deep copy of the rules so we can keep a version without AttrName Rewrite
      pro_rules2 = Marshal.load(Marshal.dump(pro_rules))
      rhs = collect_rhs(pro_rules)
      reset_instance_vars
      rhs_pos = collect_rhs(AttrNameRewriter.new(@bud_instance).process(pro_rules2))
    end
    record_rule(lhs, op, rhs_pos, rhs)
    drain(exp)
  end

  # We want to rewrite "map" calls on BudCollections to "pro" calls. It is hard
  # to do this accurately (issue #225), so we just replace map calls liberally
  # and define Enumerable#pro as an alias for "map".
  def map2pro(exp)
    # the non-superator case
    if exp[1] and exp[1][0] and exp[1][0] == :iter \
      and exp[1][1] and exp[1][1][1] and exp[1][1][1][0] == :call
      if exp[1][1][2] == :map
        exp[1][1][2] = :pro
      end
    # the superator case
    elsif exp[1] and exp[1][0] == :call and (exp[1][2] == :~ or exp[1][2] == :+)
      if exp[1][1] and exp[1][1][1] and exp[1][1][1][2] == :map
        exp[1][1][1][2] = :pro
      end
    end  
    exp
  end

  def drain(exp)
    exp.shift until exp.empty?
    return ""
  end
end

# Rewrite named-column refs to positional refs
class AttrNameRewriter < SexpProcessor # :nodoc: all
  def initialize(bud_instance)
    super()
    self.require_empty = false
    self.expected = Sexp
    @iterhash ||= {}
    @collnames = []
    @bud_instance = bud_instance
  end

  # some icky special-case parsing to find mapping between collection names and iter vars
  def process_iter(exp)
    if exp[1] and exp[1][0] == :call
      gather_collection_names(exp[1])

      # now find iter vars and match up
      if exp[2] and exp[2][0] == :lasgn and @collnames.size == 1 #single-table iter
        raise Bud::CompileError, "nested redefinition of block variable \"#{exp[2][1]}\" not allowed" if @iterhash[exp[2][1]]
        @iterhash[exp[2][1]] = @collnames[0]
      elsif exp[2] and exp[2][0] == :lasgn and @collnames.size > 1 # join iter with lefts/rights
        if exp[1] and exp[1][2] == :lefts
          @iterhash[exp[2][1]] = @collnames[0] 
        elsif exp[1] and exp[1][2] == :rights
          @iterhash[exp[2][1]] = @collnames[1]
        else
          raise Bud::CompileError, "nested redefinition of block variable \"#{exp[2][1]}\" not allowed" if @iterhash[exp[2][1]]
        end
      elsif exp[2] and exp[2][0] == :masgn and not @collnames.empty? # join or reduce iter
        return unless exp[2][1] and exp[2][1][0] == :array
        if exp[1][2] == :reduce
          unless @collnames.length == 1
            raise BudError, "reduce should only one associated collection, but has #{@collnames.inspect}"
          end
          @iterhash[exp[2][1][2][1]] = @collnames.first
        else #join
          @collnames.each_with_index do |c, i|
            next unless exp[2][1][i+1] and exp[2][1][i+1][0] == :lasgn
            @iterhash[exp[2][1][i+1][1]] = c
          end
        end
      end
    end
    (1..(exp.length-1)).each {|i| exp[i] = process(exp[i])}
    exp
  end

  def register_scratch(name, schemahash)
    # define a scratch with the name and schema in this rename block
    hash, key_array, val_array = schemahash
    key_array ||= []
    val_array ||= []
    key_cols = key_array.map{|i| i[1] if i.class <= Sexp}.compact
    val_cols = val_array.map{|i| i[1] if i.class <= Sexp}.compact
    @bud_instance.scratch(name, key_cols=>val_cols)
  end

  def gather_collection_names(exp)
    if exp[0] == :call and exp[1].nil?
      @collnames << exp[2]
    elsif exp[2] and exp[2] == :rename
      arglist, namelit, schemahash = exp[3]
      # and add name to @collnames
      @collnames << namelit[1]
    else
      exp.each { |e| gather_collection_names(e) if e and e.class <= Sexp }
    end
  end

  def process_call(exp)
    call, recv, op, args = exp

    if op == :rename
      arglist, namelit, schemahash = args
      register_scratch(namelit[1], schemahash)
    end
    if recv and recv.class == Sexp and recv.first == :lvar and recv[1] and @iterhash[recv[1]]
      if @bud_instance.respond_to?(@iterhash[recv[1]])
        if @bud_instance.send(@iterhash[recv[1]]).class <= Bud::BudCollection
          schema = @bud_instance.send(@iterhash[recv[1]]).schema
          if op != :[] and @bud_instance.send(@iterhash[recv[1]]).respond_to?(op)
            # if the op is an attribute name in the schema, col is its index
            col = schema.index(op) unless schema.nil?
            unless col.nil?
              op = :[]
              args = s(:arglist, s(:lit, col))
            end
          end
        end
        return s(call, recv, op, args)
      end
    end
    return s(call, process(recv), op, process(args))
  end
end

# Given a table of renames from x => y, replace all calls to "x" with calls to
# "y" instead. We don't try to handle shadowing due to block variables: if a
# block references a block variable that shadows an identifier in the rename
# tbl, it should appear as an :lvar node rather than a :call, so we should be
# okay.
class CallRewriter < SexpProcessor # :nodoc: all
  def initialize(rename_tbl)
    super()
    self.require_empty = false
    self.expected = Sexp
    @rename_tbl = rename_tbl
  end

  def process_call(exp)
    tag, recv, meth_name, args = exp

    if @rename_tbl.has_key? meth_name
      meth_name = @rename_tbl[meth_name] # No need to deep-copy Symbol
    end

    recv = process(recv)
    args = process(args)

    s(tag, recv, meth_name, args)
  end
end

# Rewrite qualified references to collections defined by an imported module. In
# the AST, this looks like a tree of :call nodes. For example, a.b.c looks like:
#
#   (:call, (:call, (:call, nil, :a, args), :b, args), :c, args)
#
# If the import table contains [a][b], we want to rewrite this into a single
# call to a__b__c, which matches how the corresponding Bloom collection will
# be name-mangled. Note that we don't currently check that a__b__c (or a.b.c)
# corresponds to an extant Bloom collection.
class NestedRefRewriter < SexpProcessor # :nodoc: all
  attr_accessor :did_work

  def initialize(import_tbl)
    super()
    self.require_empty = false
    self.expected = Sexp
    @import_tbl = import_tbl
    @did_work = false
  end

  def process_call(exp)
    return exp if @import_tbl.empty?
    tag, recv, meth_name, args = exp

    catch :skip do
      recv_stack = make_recv_stack(recv)
      throw :skip unless recv_stack.length > 0

      lookup_tbl = @import_tbl
      new_meth_name = ""
      until recv_stack.empty?
        m = recv_stack.pop
        throw :skip unless lookup_tbl.has_key? m

        new_meth_name += "#{m}__"
        lookup_tbl = lookup_tbl[m]
      end

      # Okay, apply the rewrite
      @did_work = true
      new_meth_name += meth_name.to_s
      recv = nil
      meth_name = new_meth_name.to_sym
    end

    recv = process(recv)
    args = process(args)

    s(tag, recv, meth_name, args)
  end

  private
  def make_recv_stack(r)
    rv = []

    while true
      break if r.nil?
      # We can exit early if we see something unexpected
      throw :skip unless r.sexp_type == :call

      recv, meth_name, args = r.sexp_body
      unless args.sexp_type == :arglist and args.sexp_body.length == 0
        throw :skip
      end

      rv << meth_name
      r = recv
    end

    return rv
  end
end

# Look for temp declarations and remove the "temp" keyword, yielding code that
# we can safely eval. We also record the set of "temp" collections we've seen,
# and provide a helper method that returns the AST of a state block that
# contains declarations for all those temp tables.
class TempExpander < SexpProcessor # :nodoc: all
  attr_reader :tmp_tables
  attr_accessor :did_work

  def initialize
    super()
    self.require_empty = false
    self.expected = Sexp

    @tmp_tables = []
    @did_work = false
  end

  def process_defn(exp)
    tag, name, args, scope = exp

    if name.to_s =~ /^__bloom__.+/
      block = scope[1]

      block.each_with_index do |n,i|
        if i == 0
          raise Bud::CompileError if n != :block
          next
        end

        # temp declarations are misparsed if the RHS contains certain constructs
        # (e.g., group, "do |f| ... end" rather than "{|f| ... }").  Rewrite to
        # correct the misparsing.
        if n.sexp_type == :iter
          iter_body = n.sexp_body

          if iter_body.first.sexp_type == :call
            call_node = iter_body.first

            _, recv, meth, meth_args = call_node
            if meth == :temp and recv.nil?
              _, lhs, op, rhs = meth_args.sexp_body.first

              old_rhs_body = rhs.sexp_body
              rhs[1] = s(:iter)
              rhs[1] += old_rhs_body
              rhs[1] += iter_body[1..-1]
              block[i] = n = call_node
              @did_work = true
            end
          end
        end

        _, recv, meth, meth_args = n
        if meth == :temp and recv.nil?
          block[i] = rewrite_temp(n)
          @did_work = true
        end
      end
    end

    s(tag, name, args, scope)
  end

  def get_state_meth(klass)
    return if @tmp_tables.empty?
    block = s(:block)

    @tmp_tables.each do |t|
      args = s(:arglist, s(:lit, t.to_sym))
      block << s(:call, nil, :temp, args)
    end

    meth_name = Module.make_state_meth_name(klass).to_s + "__tmp"
    return s(:defn, meth_name.to_sym, s(:args), s(:scope, block))
  end

  private
  def rewrite_temp(exp)
    _, recv, meth, args = exp

    raise Bud::CompileError unless recv == nil
    nest_call = args.sexp_body.first
    raise Bud::CompileError unless nest_call.sexp_type == :call

    nest_recv, nest_op, nest_args = nest_call.sexp_body
    raise Bud::CompileError unless nest_recv.sexp_type == :lit

    tmp_name = nest_recv.sexp_body.first
    @tmp_tables << tmp_name
    new_recv = s(:call, nil, tmp_name, s(:arglist))
    return s(:call, new_recv, nest_op, nest_args)
  end
end

class DefnRenamer < SexpProcessor # :nodoc: all
  def initialize(local_name, rename_tbl)
    super()
    self.require_empty = false
    self.expected = Sexp
    @local_name = local_name
    @rename_tbl = rename_tbl
  end

  def process_defn(exp)
    tag, name, args, scope = exp
    name_s = name.to_s

    if name_s =~ /^__bootstrap__.+$/
      new_name = name_s.sub(/^(__bootstrap__)(.+)$/, "\\1#{@local_name}__\\2")
    elsif name_s =~ /^__state\d+__/
      new_name = name_s.sub(/^(__state\d+__)(.*)$/, "\\1#{@local_name}__\\2")
    elsif name_s =~ /^__bloom__.+$/
      new_name = name_s.sub(/^(__bloom__)(.+)$/, "\\1#{@local_name}__\\2")
    else
      new_name = "#{@local_name}__#{name_s}"
    end

    new_name = new_name.to_sym
    @rename_tbl[name] = new_name

    # Note that we don't bother to recurse further into the AST: we're only
    # interested in top-level :defn nodes.
    s(tag, new_name, args, scope)
  end
end

