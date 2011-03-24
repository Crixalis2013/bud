module Bud
  class BudJoin < BudCollection
    attr_accessor :rels, :origrels

    def initialize(rellist, bud_instance, preds=nil)
      @schema = []
      otherpreds = nil
      @origrels = rellist
      @bud_instance = bud_instance
      @localpreds = nil
			
			preds = decomp_preds(*preds)

      # extract predicates on rellist[0] and let the rest recurse
      unless preds.nil?
        @localpreds = preds.reject { |p| p[0][0] != rellist[0].tabname and p[1][0] != rellist[0].tabname }
				canonicalize_localpreds(rellist)
        otherpreds = preds.reject { |p| p[0][0] == rellist[0].tabname or p[1][0] == rellist[0].tabname}
        otherpreds = nil if otherpreds.empty?
      end
      if rellist.length == 2 and not otherpreds.nil?
        raise BudError, "join predicates don't match tables being joined: #{otherpreds.inspect}"
      end

      # recurse to form a tree of binary BudJoins
      @rels = [rellist[0]]
      @rels << (rellist.length == 2 ? rellist[1] : BudJoin.new(rellist[1..rellist.length-1], @bud_instance, otherpreds))

      # derive schema: one column for each table.
      # unnamed inputs become "t_i" for position i
      # duplicated inputs get distinguishing numeral
      @schema = []
      index = 0
      rellist.reduce({}) do |memo, r|
        index += 1
        if !r.respond_to?(:tabname)
          @schema << "t_#{index}".to_sym
        else
          memo[r.tabname.to_s] ||= 0
          @schema << (r.tabname.to_s + (memo[r.tabname.to_s] > 0 ? "_" + memo[r.tabname.to_s].to_s : "")).to_sym
          memo[r.tabname.to_s] += 1
        end
        memo
      end
    end

		def self.natural_preds(bud_instance, rels)
			preds = []
	    rels.each do |r|
	      rels.each do |s|
	        matches = r.schema & s.schema
	        matches.each do |c|
	          preds << [bud_instance.send(r.tabname).send(c), bud_instance.send(s.tabname).send(c)] unless r.tabname.to_s >= s.tabname.to_s
	        end
	      end
	    end
	    preds.uniq
		end
		
		# currently supports two options for equijoin predicates:
		#    general form: an array of arrays capturing a conjunction of equiv. classes
		#          [[table1.col1, table2.col2, table3.col3], [table1.col2, table2.col3]]
		#    common form: a hash capturing equality of a column on left with one on right.
		#          :col1 => :col2  (same as  lefttable.col1 => righttable.col2)
		def pairs(*preds, &blk)
			unless preds.nil?
				if preds.size == 1 and preds[0].class <= Hash
					predarray = preds[0].map do |k,v|
						if k.class != v.class
            	raise Bud::CompileError, "inconsistent attribute ref style #{k.inspect} => #{v.inspect}"
						elsif k.class <= Array
							[k,v]
						elsif k.class <= Symbol
							begin
								[@rels[0].send(k), @rels[1].send(v)]
							rescue
								raise Bud::CompileError, "unknown attribute ref in #{k.inspect} => #{v.inspect}"
					    end
					  else
							raise Bud::CompileError, "invalid attribute ref in #{k.inspect} => #{v.inspect}"
						end
					end
					@localpreds = decomp_preds(*predarray)
				else
					@localpreds = decomp_preds(*preds)
				end
				canonicalize_localpreds(@rels)
			end
			map(&blk)
		end
		
		def matches(&blk)
			preds = BudJoin::natural_preds(@bud_instance, @rels)
			pairs(*preds, &blk)
		end
			
		def lefts(preds, &blk)
			pairs(*preds) {|l, r| l}
		end

		def rights(preds, &blk)
			pairs(*preds) {|l, r| r}
		end

	  def decomp_preds(*preds)
	    # decompose each pred into a binary pred
		  return nil if preds.nil? or preds.empty? or preds == [nil]
	    newpreds = []
	    preds.each do |p|
	      p.each_with_index do |c, i|
	        newpreds << [p[i], p[i+1]] unless p[i+1].nil?
	      end
	    end
	    newpreds
	  end	  
	
		def canonicalize_localpreds(rellist)
			return if @localpreds.nil?
			@localpreds.each do |p|
        if p[1][0] == rellist[0].tabname
          @localpreds.delete(p)
          @localpreds << [p[1], p[0]]
        end
      end
		end

    def flatten
      flat_schema = @rels.map{|r| r.schema}.flatten(1)
      dupfree_schema = []
      flat_schema.reduce({}) do |memo, r|
        memo[r] ||= 0
        dupfree_schema << (r.to_s + (memo[r] > 0 ? "_" + memo[r].to_s : "")).to_sym
        memo[r] += 1
        memo
      end
      retval = BudScratch.new('temp_flatten', bud_instance, dupfree_schema)
      retval.merge(self.map{|r,s| r+s}, retval.storage)
    end

    def do_insert(o, store)
      raise BudError, "no insertion into joins"
    end

    def inspected
      if @rels.length == 2 then
        # fast common case
        self.map{|r1, r2| ["\[ #{r1.inspect} #{r2.inspect} \]"]}
      else
        str = "self.map\{|"
        (1..@rels.length-1).each{|i| str << "r#{i},"}
        str << "r#{@rels.length}| \[\"\[ "
        (1..@rels.length).each{|i| str << "\#\{r#{i}.inspect\} "}
        str << "\]\"\]\}"
        eval(str)
      end
    end


    def each(mode=:both, &block)
      mode = :storage if @bud_instance.stratum_first_iter
      if mode == :storage
        methods = [:storage]
      else
        methods = [:delta, :storage]
      end

      methods.each do |collection1|
        methods.each do |collection2|
          next if (mode == :delta and collection1 == :storage and collection2 == :storage)
          if @localpreds.nil? or @localpreds.empty?
            nestloop_join(collection1, collection2, &block)
          else
            hash_join(collection1, collection2, &block)
          end
        end
      end
    end
    
    def each_from_sym(buf_syms, &block)
      buf_syms.each do |s|
        each(s, &block)
      end
    end

    # def each_storage(&block)
    #   each(:storage, &block)
    # end
    # 
    # # this needs to be made more efficient!
    # def each_delta(&block)
    #   each(:delta, &block)
    # end

    def test_locals(r, s, *skips)
      retval = true
      if (@localpreds and skips and @localpreds.length > skips.length)
        # check remainder of the predicates
        @localpreds.each do |pred|
          next if skips.include? pred
          r_offset, s_index, s_offset = join_offsets(pred)
          if r[r_offset] != s[s_index][s_offset]
            retval = false
            break
          end
        end
      end
      return retval
    end

    def nestloop_join(collection1, collection2, &block)
      @rels[0].each_from_sym([collection1]) do |r|
        @rels[1].each_from_sym([collection2]) do |s|
          s = [s] if origrels.length == 2
          yield([r] + s) if test_locals(r, s)
        end
      end
    end

    def join_offsets(pred)
      build_entry = pred[1]
      build_name, build_offset = build_entry[0], build_entry[1]
      probe_entry = pred[0]
      probe_name, probe_offset = probe_entry[0], probe_entry[1]

      # determine which subtuple of s contains the table referenced in RHS of pred
      # note that s doesn't contain the first entry in rels, which is r
      index = 0
      origrels[1..origrels.length].each_with_index do |t,i|
        if t.tabname == pred[1][0]
          index = i
          break
        end
      end

      return probe_offset, index, build_offset
    end

    def hash_join(collection1, collection2, &block)
      # hash join on first predicate!
      ht = {}

      probe_offset, build_tup, build_offset = join_offsets(@localpreds.first)

      # build the hashtable on s!
      rels[1].each_from_sym([collection2]) do |s|
        s = [s] if origrels.length == 2
        attrval = s[build_tup][build_offset]
        ht[attrval] ||= []
        ht[attrval] << s
      end

      # probe the hashtable!
      rels[0].each_from_sym([collection1]) do |r|
        next if ht[r[probe_offset]].nil?
        ht[r[probe_offset]].each do |s|
          retval = [r] + s
          yield(retval) if test_locals(r, s, @localpreds.first)
        end
      end
    end
  end

  class BudLeftJoin < BudJoin
    def initialize(rellist, bud_instance, preds=nil)
      raise(BudError, "Left Join only defined for two relations") unless rellist.length == 2
      super(rellist, bud_instance, preds)
      @origpreds = preds
    end

    def each(&block)
      super(&block)
      # previous line finds all the matches.
      # now its time to ``preserve'' the outer tuples with no matches.
      # this is totally inefficient: we should fold the identification of non-matches
      # into the join algorithms.  Another day.
      # our trick: for each tuple of the outer, generate a singleton relation
      # and join with inner.  If result is empty, preserve tuple.
      @rels[0].each do |r|
        t = @origrels[0].clone_empty
        t.insert(r)
        j = BudJoin.new([t,@origrels[1]], @bud_instance, @origpreds)
        next if j.any?
        nulltup = @origrels[1].null_tuple
        yield [r, nulltup]
      end
    end
  end
end