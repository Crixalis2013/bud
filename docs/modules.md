# Code Structuring and Reuse in BUD

## Language Support

### Ruby Mixins

The basic unit of reuse in BUD is the mixin functionality provided by Ruby itself.  BUD code is structured into modules, each of which may have its own __state__ and__bootstrap__ block and any number of __bloom__ blocks (described below).  A module or class may mix in a BUD module via Ruby's _include_ statement.  _include_ causes the specified module's code to be expanded into the local scope.

### Bloom ``Baskets'' (Bouquets?)

While the order and grouping of BUD rules have no semantic significance, rules can be grouped and tagged within a single module using __bloom__ blocks or baskets.  Baskets serve two purposes:
 
 1. Improving readability by grouping related or dependent rules together.
 2. Supporting name-based overriding.

(1) is self-explanatory.  (2) is one of several extensibility mechanisms provided by BUD.  If a Module B includes a module A which contains a basket X, B may supply a basket X and in so doing replaces the set of rules defined by A with its own set.  For example:

    require 'rubygems'
    require 'bud'
    
    module Hello
      state do
        interface input, :stim
      end
      bloom :hi do
        stdio <~ stim {|s| ["Hello, #{s.val}"]}
      end
    end
    
    module HelloTwo
      include Hello
      bloom :hi do
        stdio <~ stim{|s| ["Hello, #{s.key}"]}
      end
    end
    
    class HelloClass
      include Bud
      include HelloTwo
    end
    
    h = HelloClass.new
    h.run_bg
    h.sync_do{h.stim <+ [[1,2]]}

The program above will print "Hello, 1", because the module HelloTwo overrides the basket named __hi__.  If we give the basket in HelloTwo a distinct name, the program will print "Hello, 1" and "Hello, 2" (in no guaranteed order).


### The BUD Module Import System

For simple programs, composing modules via _include_ is often sufficient.  But the flat namespace provided by mixins can make it difficult or impossible to support certain types of reuse.  Consider a module Q that provides a queue-like functionality via an input interface _enqueue_ and an output interface _dequeue_, each with a single attribute (payload).  A later module may wish to employ two queues (say, to implement a scheduler).  But it cannot include Q twice!  It would be necessary to rewrite Q's interfaces so as to support multiple ``users.'' 

In addition to _include_, BUD supports the _import_ keyword, which instantiates a BUD module under a namespace alias.  For example:

    module UserCode
      import Q => :q1
      import Q => :q2

      bloom do
        # insert into the first queue
        q1.enqueue <= [....]
      end
    end


## Techniques

### Structuring 

In summary, BUD extends the basic Ruby code structuring mechanisms (classes and modules) with rule baskets, for finer-granularity grouping of rules 
within modules, and the import system, for scoped inclusion.

### Composition

Basic code composition can achieved using the Ruby mixin system.  If the flat namespace causes ambiguity (as above) or hinders readability, the import system provides the ability to scope code inclusions.

### Extension and Overriding

Extending the existing functionality of a BUD program can be achieved in a number of ways.  The simplest (but arguably least flexible) is via basket overriding, as described in the Hello example above.  

The import system can be used to implement finer-grained overriding, at the collection level.  Consider a module BlackBox that provides an input interface __iin__ and an output interface __iout__.  Suppose that we wish to "use" BlackBox, but need to provide additional functionality.  We may extend one or both of its interfaces by _import_'ing BlackBox, redeclaring the interfaces, and gluing them together.  For example, the module UsesBlackBox shown below interposes additional logic (indicated by ellipses) upstream of BlackBox's input interface, and provides ``extended'' BlackBox functionality.

    module UsesBlackBox
      import BlackBox => :bb
      state do
        interface input, :iin
        interface output, :iout
      end

      bloom do
        [ .... ] <= iin
        bb.iin <= [ .... ]
        iout <= bb.iout
      end
    end

### Abstract Interfaces and Concrete Implementations

In the previous example, two different implementations (UsesBlackBox and its dependency BlackBox) had the same externally visible interface: inserting tuples into __iin__ causes tuples to appear in __iout__.  In some sense, the definition of this pair of interfaces comprises an abstract contract which both implementations implement -- and the dependency of UsesBlackBox on Blackbox is just a detail of UsesBlackBox's implementation.

The basic Ruby module system inherited by Bud may be used, by convention, to enable code reuse and hiding via the separation of abstract interfaces and concrete implementations.  Instead of reiterating the schema definitions in multiple state blocks, we will often instead declare a protocol module as follows:

    module BBProtocol
      # Contract: do XXXXXXXXXXX
      state do
        interface input, :iin
        interface output, :iout
      end
    end

Each implementation of the protocol would then include BBProtocol.  Though the interpreter treats this as an ordinary Ruby mixin, the interpretation is that by including BBProtocol, both BlackBox and UsesBlackBox _implement_ the protocol.  A downstream developer may then write code against the external interface, committing only when necessary to a fully-specified implmentation.