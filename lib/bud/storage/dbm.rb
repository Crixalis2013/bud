require 'dbm'

module Bud
  # Persistent table implementation based on ndbm.
  class BudDbmTable < BudCollection # :nodoc: all
    def initialize(name, bud_instance, given_schema)
      dbm_dir = bud_instance.options[:dbm_dir]
      raise Bud::Error, "dbm support must be enabled via 'dbm_dir'" unless dbm_dir
      if bud_instance.port.nil?
        raise Bud::Error, "use of dbm storage requires an explicit port to be specified in Bud initialization options"
      end

      unless File.exists?(dbm_dir)
        Dir.mkdir(dbm_dir)
        puts "Created directory: #{dbm_dir}" unless bud_instance.options[:quiet]
      end
      dirname = "#{dbm_dir}/bud_#{bud_instance.port}"
      unless File.exists?(dirname)
        Dir.mkdir(dirname)
        puts "Created directory: #{dirname}" unless bud_instance.options[:quiet]
      end

      super(name, bud_instance, given_schema)
      @to_delete = []

      db_fname = "#{dirname}/#{name}.dbm"
      flags = DBM::WRCREAT
      if bud_instance.options[:dbm_truncate] == true
        flags |= DBM::NEWDB
      end
      @dbm = DBM.open(db_fname, 0666, flags)
      if @dbm.nil?
        raise Bud::Error, "failed to open dbm database '#{db_fname}': #{@dbm.errmsg}"
      end
    end

    def init_storage
      # XXX: we can't easily use the @storage infrastructure provided by
      # BudCollection; issue #33
      @storage = nil
    end

    def [](key)
      check_enumerable(key)
      key_s = MessagePack.pack(key)
      val_s = @dbm[key_s]
      if val_s
        return make_tuple(key, MessagePack.unpack(val_s))
      else
        return @delta[key]
      end
    end

    def has_key?(k)
      check_enumerable(k)
      key_s = MessagePack.pack(k)
      return true if @dbm.has_key? key_s
      return @delta.has_key? k
    end

    def include?(tuple)
      key = get_key_vals(tuple)
      value = self[key]
      return (value == tuple)
    end

    def make_tuple(k_ary, v_ary)
      t = Array.new(k_ary.length + v_ary.length)
      @key_colnums.each_with_index do |k,i|
        t[k] = k_ary[i]
      end
      val_cols.each_with_index do |c,i|
        t[cols.index(c)] = v_ary[i]
      end
      tuple_accessors(t)
    end

    def each(&block)
      each_from([@delta], &block)
      each_storage(&block)
    end

    def each_from(bufs, &block)
      bufs.each do |b|
        if b == @storage then
          each_storage(&block)
        else
          b.each_value do |v|
            tick_metrics if bud_instance.options[:metrics]
            yield v
          end
        end
      end
    end

    def each_storage(&block)
      @dbm.each do |k,v|
        k_ary = MessagePack.unpack(k)
        v_ary = MessagePack.unpack(v)
        tick_metrics if bud_instance.options[:metrics]
        yield make_tuple(k_ary, v_ary)
      end
    end

    def flush
    end

    def close
      @dbm.close unless @dbm.nil?
      @dbm = nil
    end

    def merge_to_db(buf)
      buf.each do |key,tuple|
        merge_tuple_to_db(key, tuple)
      end
    end

    def merge_tuple_to_db(key, tuple)
      val = @val_colnums.map {|c| tuple[c]}
      key_s = MessagePack.pack(key)
      val_s = MessagePack.pack(val)
      if @dbm.has_key?(key_s)
        old_tuple = self[key]
        raise_pk_error(tuple, old_tuple) if tuple != old_tuple
      else
        @dbm[key_s] = val_s
      end
    end

    # move deltas to on-disk storage, and new_deltas to deltas
    def tick_deltas
      merge_to_db(@delta)
      @delta = @new_delta
      @new_delta = {}
    end

    superator "<-" do |o|
      o.each do |tuple|
        @to_delete << tuple unless tuple.nil?
      end
    end

    def insert(tuple)
      key = get_key_vals(tuple)
      merge_tuple_to_db(key, tuple)
    end

    alias << insert

    # Remove to_delete and then add pending to db
    def tick
      raise Bud::Error, "orphaned tuples in @delta for #{@tabname}" unless @delta.empty?
      raise Bud::Error, "orphaned tuples in @new_delta for #{@tabname}" unless @new_delta.empty?

      @to_delete.each do |tuple|
        k = get_key_vals(tuple)
        k_str = MessagePack.pack(k)
        cols_str = @dbm[k_str]
        unless cols_str.nil?
          db_cols = MessagePack.unpack(cols_str)
          delete_cols = val_cols.map{|c| tuple[cols.index(c)]}
          if db_cols == delete_cols
            @dbm.delete k_str
          end
        end
      end
      @to_delete = []

      merge_to_db(@pending)
      @pending = {}

      flush
    end

    def method_missing(sym, *args, &block)
      @dbm.send sym, *args, &block
    end
  end
end
