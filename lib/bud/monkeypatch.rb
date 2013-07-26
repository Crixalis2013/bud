# We monkeypatch Module to add support for Bloom's syntax additions: "state",
# "bloom", and "bootstrap" blocks, plus the "import" statement.

require 'bud/source'

class Class
  def modules
    a = self.ancestors
    a[1..a.index(superclass)-1]
  end
end

class Bud::TupleStruct < Struct
  include Comparable

  attr_accessor :source_address

  def self.new_struct(tbl_name, cols)
    c = Bud::TupleStruct.new(*cols)
    c.instance_variable_set(:@__table_name, tbl_name)
    c
  end

  # XXX: The table_name of a tuple might be incorrect in certain obscure
  # circumstances -- e.g., when passing tuples through deductive rules with no
  # code blocks, we don't convert the underlying tuple from one Struct instance
  # to another.
  def table_name
    self.class.instance_variable_get(:@__table_name)
  end

  # Note that we implement structural equality -- two tuples from different
  # tables are considered equal if they have the same number of columns and the
  # same content for each column (column names might differ).
  # XXX: Shouldn't we implement <=> for Array as well?
  def <=>(o)
    if o.kind_of? Bud::TupleStruct
      o_len = o.length
      self.each_with_index do |e, i|
        break if i >= o_len
        other = o[i]
        next if e == other
        return e <=> other
      end
      return self.source_address <=> o.source_address ||
             self.length <=> o_len
    elsif o.nil?
      return nil
    else
      raise "Comparison (<=>) between #{o.class} and #{self.class} not implemented"
    end
  end

  def ==(o)
    unless o.kind_of? Bud::TupleStruct or o.class == Array
      return false
    end

    return false if self.length != o.length
    return false if o.kind_of? Bud::TupleStruct and
                    self.source_address != o.source_address
    self.each_with_index do |el, i|
      return false if el != o[i]
    end
    return true
  end

  def hash
    h = 17
    # When combining hash functions, we don't use XOR (since it is commutative);
    # rather, we use a trick per Bob Jenkins.
    self.each {|e| h = (h * 31) + e.hash}
    h ^= @source_address.hash
    h
  end

  def eql?(o)
    self == o
  end

  def +(o)
    self.to_ary + o.to_ary
  end

  def to_msgpack(out=nil)
    self.to_a.to_msgpack(out)
  end

  def inspect
    self.to_a.inspect
  end

  alias :to_s :inspect
  alias :to_ary :to_a
end

# XXX: TEMPORARY/UGLY hack to ensure that arrays and structs compare. This can be
# removed once tests are rewritten.
class Array
  alias :oldeq :==
  def ==(o)
    o = o.to_a if o.kind_of? Bud::TupleStruct
    self.oldeq(o)
  end
end


$moduleWrapper = {} # module => wrapper class.  See import below.
class Module
  def modules
    ancestors[1..-1]
  end

  # import another module and assign to a qualifier symbol: <tt>import MyModule => :m</tt>
  def import(spec)
    raise Bud::CompileError unless (spec.class <= Hash and spec.length == 1)
    mod, local_name = spec.first
    raise Bud::CompileError unless (mod.class <= Module and local_name.class <= Symbol)
    if mod.class <= Class
      raise Bud::CompileError, "import must be used with a Module, not a Class"
    end

    # A statement like this:
    #   import MyModule => :m
    # is translated as follows. First, module MyModule is made instantiable by wrapping it in a class
    #   class MyModule__wrap__
    #     include Bud
    #     include MyModule
    #   end
    #
    # Then introduce a method "m", the import binding name, in the calling module/class
    # (the one with the import statement). This returns an instance of the wrapped class.
    #   inst = MyModule__wrap__.new
    #   def m
    #      inst
    #   end

    mod, local_name = spec.first

    if self.method_defined? local_name
      raise Bud::CompileError, "#{local_name} is already taken"
    else
      src = %Q{
        def #{local_name}
          @#{local_name}
        end
        def #{local_name}=(val)
          raise Bud::Error, "type error: expecting an instance of #{mod}" unless val.kind_of? #{mod}
          @#{local_name} = val
        end
      }
      self.class_eval src
    end

    import_tbl = self.bud_import_table
    import_tbl[local_name] = mod
  end

  def bud_import_table() #:nodoc: all
    @bud_import_tbl ||= {}
    @bud_import_tbl
  end

  # the block of Bloom collection declarations.  one per module.
  def state(&block)
    meth_name = Module.make_state_meth_name(self)
    define_method(meth_name, &block)
  end

  # a ruby block to be run before timestep 1.  one per module.
  def bootstrap(&block)
    meth_name = "__bootstrap__#{Module.get_class_name(self)}".to_sym
    define_method(meth_name, &block)
  end

  # bloom statements to be registered with Bud runtime.  optional +block_name+
  # assigns a name for the block; this is useful documentation, and also allows
  # the block to be overridden in a child class.
  def bloom(block_name=nil, &block)
    # If no block name was specified, generate a unique name
    if block_name.nil?
      @block_id ||= 0
      block_name = "#{Module.get_class_name(self)}__#{@block_id}".to_sym
      @block_id += 1
    else
      unless block_name.class <= Symbol
        raise Bud::CompileError, "block name must be a symbol: #{block_name}"
      end
    end

    # Note that we don't encode the module name ("self") into the name of the
    # method. This allows named blocks to be overridden (via inheritance or
    # mixin) in the same way as normal Ruby methods.
    meth_name = "__bloom__#{block_name}"

    # Don't allow duplicate named bloom blocks to be defined within a single
    # module; this indicates a likely programmer error.
    if instance_methods(false).include?(meth_name) ||
       instance_methods(false).include?(meth_name.to_sym)
      raise Bud::CompileError, "duplicate block name: '#{block_name}' in #{self}"
    end
    ast = Source.read_block(caller[0]) # pass in caller's location via backtrace

    # ast corresponds only to the statements of the block. Wrap it in a method
    # definition for backward compatibility for now.

    # If the block contained multiple statements, the AST will have a top-level
    # :block node. Since ruby_parser ASTs for method definitions don't contain
    # such a node, remove it.
    if ast.nil?
      ast = []
    elsif ast.sexp_type == :block
      ast = ast.sexp_body
    else
      ast = [ast]
    end
    ast = s(:defn, meth_name.to_sym, s(:args), *ast)
    unless self.respond_to? :__bloom_asts__
      def self.__bloom_asts__
        @__bloom_asts__ ||= {}
        @__bloom_asts__
      end
    end
    __bloom_asts__[meth_name] = ast
    define_method(meth_name.to_sym, &block)
  end

  # Return a string with a version of the class name appropriate for embedding
  # into a method name. Annoyingly, if you define class X nested inside
  # class/module Y, X's class name is the string "Y::X". We don't want to define
  # method names with semicolons in them, so just return "X" instead.
  private
  def self.get_class_name(klass)
    (klass.name.nil? or klass.name == "") \
      ? "Anon#{klass.object_id}" \
      : klass.name.split("::").last
  end

  # State method blocks are named using an auto-incrementing counter. This is to
  # ensure that we can rediscover the possible dependencies between these blocks
  # after module import (see Bud#call_state_methods).
  def self.make_state_meth_name(klass)
    @state_meth_id ||= 0
    r = "__state#{@state_meth_id}__#{Module.get_class_name(klass)}".to_sym
    @state_meth_id += 1
    return r
  end
end


module Enumerable
  public
  # We rewrite "map" calls in Bloom blocks to invoke the "pro" method
  # instead. This is fine when applied to a BudCollection; when applied to a
  # normal Enumerable, just treat pro as an alias for map.
  def pro(&blk)
    map(&blk)
  end
end
