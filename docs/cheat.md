# Bud Cheat Sheet #

## General Bloom Syntax Rules ##
Bloom programs are unordered sets of statements.<br>
Statements are delimited by semicolons (;) or newlines. <br>
As in Ruby, backslash is used to escape a newline.<br>

## Simple embedding of Bud in a Ruby Class ##
    require 'bud'

    class Foo
      include Bud
        
      state do
        ...
      end
        
      bloom do
        ...
      end
    end
    
## State Declarations ##
A `state` block contains Bud collection definitions. A Bud collection is a *set*
of *facts*; each fact is an array of Ruby values. Note that collections do not
contain duplicates (inserting a duplicate fact into a collection is ignored).

Like a table in a relational databas, a subset of the columns in a collection
makeup the collection's _key_. Attempting to insert two facts into a collection
that agree on the key columns (but are not duplicates) results in a runtime
exception.

### Default Declaration Syntax ###
*BudCollection :name, [keys] => [values]*

### table ###
Contents persist in memory until explicitly deleted.<br>
Default attributes: `[:key] => [:val]`

    table :keyvalue
    table :composite, [:keyfield1, :keyfield2] => [:values]
    table :noDups, [:field1, field2]

### scratch ###
Contents emptied at start of each timestep.<br>
Default attributes: `[:key] => [:val]`

    scratch :stats

### interface ###
Scratch collections, used as connection points between modules.<br>
Default attributes: `[:key] => [:val]`

    interface input, :request
    interface output, :response

### channel ###
Network channel manifested as a scratch collection.<br>
Facts that are inserted into a channel are sent to a remote host; the address of the remote host is specified in an attribute of the channel that is denoted with `@`.<br>
Default attributes: `[:@address, :val] => []`

(Bloom statements with channel on lhs must use async merge (`<~`).)

    channel :msgs
    channel :req_chan, [:cartnum, :storenum, :@server] => [:command, :params]

### periodic ###
System timer manifested as a scratch collection.<br>
System-provided attributes: `[:key] => [:val]`<br>
&nbsp;&nbsp;&nbsp;&nbsp; (`key` is a unique ID, `val` is a Ruby Time converted to a string.)<br>
State declaration includes interval (in seconds).

(periodic can only be used on rhs of a Bloom statement.)

    periodic :timer, 0.1

### stdio ###
Built-in scratch collection mapped to Ruby's `$stdin` and `$stdout`<br>
System-provided attributes: `[:line] => []`

Statements with stdio on lhs must use async merge (`<~`).<br>
To capture `$stdin` on rhs, instantiate Bud with `:read_stdin` option.<br>

### dbm_table ###
Table collection mapped to a [DBM] (http://en.wikipedia.org/wiki/Dbm) store.<br>
Default attributes: `[:key] => [:val]`

    dbm_table :t1
    dbm_table :t2, [:k1, :k2] => [:v1, :v2]

### tctable ###
Table collection mapped to a [Tokyo Cabinet](http://fallabs.com/tokyocabinet/) store.<br>
Default attributes: `[:key] => [:val]`

    tctable :t1
    tctable :t2, [:k1, :k2] => [:v1, :v2]

### zktable ###
Table collection mapped to an [Apache Zookeeper](http://hadoop.apache.org/zookeeper/) store.<br>
System-provided attributes: `[:key] => [:val]`<br>
State declaration includes Zookeeper path and optional TCP string (default: "localhost:2181")<br>

    zktable :foo, "/bat"
    zktable :bar, "/dat", "localhost:2182"


## Bloom Statements ##
*lhs BloomOp rhs*

Left-hand-side (lhs) is a named `BudCollection` object.<br>
Right-hand-side (rhs) is a Ruby expression producing a `BudCollection` or `Array` of `Arrays`.<br>
BloomOp is one of the 4 operators listed below.

### Bloom Operators ###
merges:

* `left <= right` &nbsp;&nbsp;&nbsp;&nbsp; (*instantaneous*)
* `left <+ right` &nbsp;&nbsp;&nbsp;&nbsp; (*deferred*)
* `left <~ right` &nbsp;&nbsp;&nbsp;&nbsp; (*asynchronous*)

delete:

* `left <- right` &nbsp;&nbsp;&nbsp;&nbsp; (*deferred*)

### Collection Methods ###
Standard Ruby methods used on a BudCollection `bc`:

implicit map:

    t1 <= bc {|t| [t.col1 + 4, t.col2.chomp]} # formatting/projection
    t2 <= bc {|t| t if t.col = 5}             # selection
    
`flat_map`:

    require 'backports' # flat_map not included in Ruby 1.8 by default

    t3 <= bc.flat_map do |t| # unnest a collection-valued attribute
      bc.col4.map { |sub| [t.col1, t.col2, t.col3, sub] }
    end

`bc.reduce`, `bc.inject`:

    t4 <= bc.reduce({}) do |memo, t|  # example: groupby col1 and count
      memo[t.col1] ||= 0
      memo[t.col1] += 1
      memo
    end

`bc.include?`:

    t5 <= bc do |t| # like SQL's NOT IN
        t unless t2.include?([t.col1, t.col2])
    end

## BudCollection-Specific Methods ##
`bc.keys`: projects `bc` to key columns<br>

`bc.values`: projects `bc` to non-key columns<br>

`bc.inspected`: shorthand for `bc {|t| [t.inspect]}`

    stdio <~ bc.inspected

`chan.payloads`: projects `chan` to non-address columns. Only defined for channels.

    # at sender
    msgs <~ requests {|r| "127.0.0.1:12345", r}
    # at receiver
    requests <= msgs.payloads

`bc.exists?`: test for non-empty collection.  Can optionally pass in a block.

    stdio <~ [["Wake Up!"] if timer.exists?]
    stdio <~ requests do |r|
      [r.inspect] if msgs.exists?{|m| r.ident == m.ident}
    end

## SQL-style grouping/aggregation (and then some) ##

* `bc.group([:col1, :col2], min(:col3))`.  *akin to min(col3) GROUP BY (col1,col2)*
  * exemplary aggs: `min`, `max`, `choose`
  * summary aggs: `sum`, `avg`, `count`
  * structural aggs: `accum`
* `bc.argmax([:col1], :col2)` &nbsp;&nbsp;&nbsp;&nbsp; *returns the bc tuple per col1 that has highest col2*
* `bc.argmin([:col1], :col2)`

### Built-in Aggregates: ###

* Exemplary aggs: `min`, `max`, `choose`
* Summary aggs: `count`, `sum`, `avg`
* Structural aggs: `accum`

Note that custom aggregation can be written using `reduce`.

## Collection Combination (Join) ###
To match items across two (or more) collections, use the `*` operator, followed by methods to filter/format the result (`pairs`, `matches`, `combos`, `lefts`, `rights`).

### Methods on Combinations (Joins) ###

`pairs(`*hash pairs*`)`: <br>
Given a `*` expression, form all pairs of items with value matches in the hash-pairs attributes.  Hash pairs can be fully qualified (`coll1.attr1 => coll2.attr2`) or shorthand (`:attr1 => :attr2`).

    # for each inbound msg, find match in a persistent buffer
    result <= (msg * buffer).pairs(:val => :key) {|m, b| [m.address, m.val, b.val] }

`combos(`*hash pairs*`)`: <br>
Alias for `pairs`, more readable for multi-collection `*` expressions.  Must use fully-qualified hash pairs.

    # the following 2 Bloom statements are equivalent to this SQL
    # SELECT r.a, s_tab.b, t.c
    #   FROM r, s_tab, t
    #  WHERE r.x = s_tab.x
    #    AND s_tab.x = t.x;

    # multiple column matches
    out <= (r * s_tab * t).combos(r.x => s_tab.x, s_tab.x => t.x) do |t1, t2, t3|
             [t1.a, t2.b, t3.c]
           end

    # column matching done per pair: this will be very slow
    out <= (r * s_tab * t).combos do |t1, t2, t3|
             [t1.a, t2.b, t3.c] if r.x == s_tab.x and s_tab.x == t.x
           end

`matches`:<br>
Shorthand for `combos` with hash pairs for all attributes with matching names.

    # Equivalent to the above statements if x is the only attribute name in common:
    out <= (r * s_tab * t).matches do {|t1, t2, t3| [t1.a, t2.b, t3.c]}
    
`lefts(`*hash pairs*`)`: <br>
Like `pairs`, but implicitly includes a block that projects down to the left item in each pair.

`rights(`*hash pairs*`)`: 
Like `pairs`, but implicitly includes a block that projects down to the right item in each pair.

`flatten`:<br>
`flatten` is a bit like SQL's `SELECT *`: it produces a collection of concatenated objects, with a schema that is the concatenation of the schemas in tablelist (with duplicate names disambiguated.) Useful for chaining to operators that expect input collections with schemas, e.g. group:

    out <= (r * s).matches.flatten.group([:a], max(:b))

`outer(`*hash pairs*`)`:<br>
Left Outer Join.  Like `pairs`, but objects in the first collection will be produced nil-padded if they have no match in the second collection.

## Temp Collections ##
`temp`<br>
Temp collections are scratches defined within a `bloom` block:

    temp :my_scratch1 <= foo

The schema of a temp collection in inherited from the rhs; if the rhs has no
schema, a simple one is manufactured to suit the data found in the rhs at
runtime: `[c0, c1, ...]`.

## Bud Modules ##
A Bud module combines state (collections) and logic (Bloom rules). Using modules allows your program to be decomposed into a collection of smaller units.

Definining a Bud module is identical to defining a Ruby module, except that the module can use the `bloom`, `bootstrap`, and `state` blocks described above.

There are two ways to use a module *B* in another Bloom module *A*:

  1. `include B`: This "inlines" the definitions (state and logic) from *B* into
     *A*. Hence, collections defined in *B* can be accessed from *A* (via the
     same syntax as *A*'s own collections). In fact, since Ruby is
     dynamically-typed, Bloom statements in *B* can access collections
     in *A*!

  2. `import B => :b`: The `import` statement provides a more structured way to
     access another module. Module *A* can now access state defined in *B* by
     using the qualifier `b`. *A* can also import two different copies of *B*,
     and give them local names `b1` and `b2`; these copies will be independent
     (facts inserted into a collection defined in `b1` won't also be inserted
     into `b2`'s copy of the collection).

## Skeleton of a Bud Module ##

    require 'rubygems'
    require 'bud'

    module YourModule
      include Bud

      state do
        ...
      end

      bootstrap do
        ...
      end

      bloom :some_stmts do
        ...
      end

      bloom :more_stmts do
        ...
      end
    end

