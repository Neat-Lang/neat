.. _manual:
.. highlight:: d

The Neat Language
=================

This document goes through every Neat language feature in approximate sequence.
The goal is that you should be able to understand the entire language by just
reading it top to bottom. But you can also use it as a reference to
quickly find how a feature works.

Lexical
-------

All Neat source files are encoded as UTF-8.

Comment syntax is as in C::

    /**
     * This is a comment. It goes from /* to */.
     */
    // This is also a comment. It goes to the end of the line.
    /* Comments can be /* nested. */ */

Comments may appear anywhere in a source file except inside identifiers or operators.

An identifier is a letter or underscore, followed by a sequence of letters, digits or underscores.

Modules
-------

A Neat source file has the extension `.nt`. Each source file corresponds to a module.
A module is a dot-separated list of packages, corresponding to folders, followed the filename.

Every file must begin with the module declaration. For instance, a file `src/hello/world.nt`::

    module hello.world;

Packages
--------

.. highlight:: none

Neat does not use includes, but instead packages. A package is a folder associated with a name::

    $ # -P<name>:<folder>[:<dependency>[,<dependency]*]
    $ neat -Proot:src src/hello/world.nt

.. highlight:: d

This defines the folder `./src` to be the package `root`. The file passed will be the module
`hello.world`, because its name will be relative to `src`.

Packages cannot access modules in other packages. To allow a package access, explicitly
list the packages that it has access to::

    $ neat -Proot:src:dep1,dep2 -Pdep1:include/dep1 -Pdep2:include/dep2

This allows the modules from package `root` in `src/` to import the modules
in `dep1` and `dep2`.
Because dependencies are explicitly listed, accidental import of modules from
an unrelated package is impossible.

Module-Level Statements
-----------------------

Import
^^^^^^

A module can import another module::

    module hello.world;

    import std.stdio;

Import is non-transitive, ie. symbols from modules imported by `std.stdio` are invisible.

Modules can be imported transitively::

    module first;

    public import second;

Now all modules that import `first` will also see the symbols in `second`.

Symbols can be imported by name: `import std.stdio : print;`.

Declaration
^^^^^^^^^^^

Structs, classes, templates and functions can be declared by name.
Every declaration can be marked as `public` or `private`; they are `public` by default.
Private declarations cannot be seen when the module is imported.

Extern(C)
^^^^^^^^^

A function can be declared as `extern(C)`. This will ensure that it matches the calling convention of the platform's native C compiler.

For example::

    extern(C) void* memcpy(void* dest, void* src, size_t n);

Note: instead of declaring lots of extern(C) functions manually, try using the
`std.macro.cimport` built-in macro! (Grep for examples.)

Expressions
-----------

Literals
^^^^^^^^

`5` is an integer literal of type `int`.

Integer literals may be arbitrarily divided by underscores for readability: `1_048_576`.

`"Hello World"` is a string literal. `string` is the same as `char[]`.

`1.2` is a `double` literal. `1.2f` is a `float` literal.

Arithmetic
^^^^^^^^^^

Binary operations can be performed on types. These are:

========= ============== ====
Operation Description    Rank
========= ============== ====
`a || b`  Boolean "or"   1
`a && b`  Boolean "and"  2
`a <= b`  Comparison     3
`a .. b`  Range          4
`a + b`   Addition       5
`a - b`   Subtraction    5
`a ~ b`   Concatenation  5
`a * b`   Multiplication 6
`a / b`   Division       6
`a | b`   Bitwise "or"   7
`a << b`  Left shift     8
`a >> b`  Right shift    8
`a ^ b`   Bitwise "xor"  9
`a & b`   Bitwise "and"  10
========= ============== ====

Boolean "or" and "and" are short-circuiting. Comparison operators are `>`, `==`, `<`, `>=`, `<=`, and `!=`.
Higher-ranked operators take precedence over lower-ranked, with boolean operators being the loosest.

Note that the placement of bitwise operators diverges from C's order.
This is because C's order is stupid^W a legacy holdover from before it had boolean operators.

Operator precedence can be clarified using parentheses: `2 * (3 + 4)` instead of `2 * 3 + 4`.

Ternary If
^^^^^^^^^^

`a if t else b` has the value of `a` if `t` is true, else it has the value of `b`.

Only the selected expression is evaluated. So if `t` is true, `b` is never evaluated.

This operator has a lower rank than any of the binary operators.

The ternary operator syntax diverges from C because `?` is already used for error propagation.

Functions
---------

A function is a series of statements operating on a list of parameters, culminating in a return value::

    ReturnType functionName(ParameterType parameterName) {
        statement;
        statement;
        statement;
        return 5;
    }
    ...
        ReturnType ret = functionName(foo);

When a function is called with `name(arg, arg)`, the arguments are passed to the parameters and
control passes to the function. The statements of the function are then executed, until control
returns to the caller when the function exits, by explicit `return` or reaching its end.

If the return type is `auto`, it is inferred from the type returned by the `return` statements
in the function body. This is called return type inference.

Call
^^^^

A function, class method or struct method can be called with a comma-separated list of arguments::

    print("Hello World");

    double d = sin(0.0);

    class.method();

When a function does not have any parameters, the empty parens can be left out, and the function will be
called implicitly::

    doWork;

This also allows struct or class methods that look like properties.

Uniform Function Call Syntax
############################

As in D, "uniform function call syntax" (UFCS) may be used. That is, if a call of the form `a.method(b)`
did not find a method `a.method` to call, it will instead be interpreted as `method(a, b)`.
This allows easily defining global functions that can be called as if they are member functions of `a`.

Named Arguments
###############

The value of every parameter on a call may be assigned by name::

    int twice(int x) { return x + x; }
    assert(twice(x=2) == 4);

This feature does not allow reordering parameters! It is purely intended to improve call readability, and to
ensure that arguments are passed to the intended parameter.

Nested functions
^^^^^^^^^^^^^^^^

Functions may be nested inside other functions. They remain valid while the surrounding function is running,
and can access variables and parameters of the containing function, that were declared before them::

    int double(int a) {
        int add(int b) {
            return a + b;
        }
        return add(a);
    }

Note that calling the nested function after the surrounding function has returned will lead to a crash!

main
^^^^

Every program must contain a function with this signature::

    void main(string[] args) {
    }

This function will be called when the program is executed.

Statements
----------

Variable declaration
^^^^^^^^^^^^^^^^^^^^

A variable can be declared like so::

    int a; // a is 0
    int b = 5;
    int c, d = 6; // c is 0
    mut int e;

Instead of a type, you may write `auto`::

    auto f = 7;

Then the type of the variable is taken from the type of the initializer.

Only mutable variables (`mut a;`) may be changed later.

Variable extraction declaration
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

When an expression is a sumtype, a subset or a single type may be extracted as such::

    (int | Error) foo;
    // `Error` will be returned if `foo` is not `int`.
    int bar <- foo;

.. note::
    This syntax is disabled pending renovations!
    The new error propagation syntax `foo?.bar` has made it superfluous.

Block statement
^^^^^^^^^^^^^^^

Multiple statements can be combined into one block::

    {
        print("Hello");
        print("World");
    }

Variables declared inside the block are not visible outside of it.

Expression statement
^^^^^^^^^^^^^^^^^^^^

Expressions can appear as statements. They are terminated with a semicolon::

    5;
    foo();

Assignment
^^^^^^^^^^

Any reference may be assigned a new value::

    mut int a = 3;
    a = 5;
    assert(a == 5);

Note that only mutable (`mut`) variables or parameters can be reassigned. As this allows
some optimizations to reference counting, non-mutable variables should be preferred.

If test
^^^^^^^

If a condition is true, execute one statement, else the other::

    if (2 + 2 == 4)
        print("2 + 2 = 4");
    else {
        print("sanity has deserted us");
    }

The condition of the `if` statement may be a variable declaration.
In that case, the condition is true if the value of the variable is true.
The variable will only be visible inside the `if` block::

    if (Foo foo = getFoo()) {
        // do foo things here
    }

`nullable Class` types are true if the class is non-null. In that case, the type
of the tested variable can be `Class`. This is the only way in which `nullable Class`
types can be converted to `Class`.

While loop
^^^^^^^^^^

While a condition is true, execute a statement::

    mut int i = 0;
    while (i < 10) { i += 1; }

For loop
^^^^^^^^

You can loop over a range expression::

    // prints 2, then 3
    for (size_t i in 2 .. 4) {
        print(ltoa(i));
    }

The type of the loop variable may be left out.

Array expressions are ranges. Array indexes can be iterated like::

    for (i, value in array) {
        array[i] = value + 2;
    }

You can also use a C-style for loop::

    for (mut int a = 0; a < 10; a += 1) { }

But this is rarely needed.

break, continue
^^^^^^^^^^^^^^^

While inside any loop, you may immediately abort and continue after the loop with `break`.

You may immediately jump to the next iteration of the loop with `continue`.

Types
-----

Basic types
^^^^^^^^^^^

====== ==================================
name   meaning
====== ==================================
int    32-bit signed integer
short  16-bit signed integer
byte   8-bit signed integer
char   8-bit UTF-8 code unit
long   64-bit signed integer
void   0-bit empty data
size_t platform-dependent unsigned word
float  32-bit IEEE floating point number
double 64-bit IEEE floating point number
====== ==================================

Array
^^^^^

`T[]` is an "array of T", what some languages call a slice.
It consists of a pointer, a length and a reference to the array object.

`T.length` is the length of the array.

`[2]` is an array of ints (`int[]`), allocated on the heap.

`array ~ array` is the concatenation of two arrays.

Appending to an array in a loop will follow a doubling strategy. It should be reasonably efficient.

`array[2]` is the third element (base-0) of the array.

Tuple
^^^^^

`(int, float)` is a tuple with two member types, `int` and `float`. Each member can have an independent value.

`(2, 3.0f)` is an expression of type `(int, float)`.

`tuple[0]` is the first member of the tuple. The index value must be an int literal.

Tuple members can be named: `(int i, float f)`. This allows accessing the member with `value.i`.

When implicitly converting tuples, tuple fields without names implicitly convert to any name, but tuple
fields with names only convert to other fields with the same name.

For example, `(2, 3)` implicitly converts to `(int from, int to)`, but `(min=2, max=3)` does not.

Sum type
^^^^^^^^

`(int | float)` is either an int or a float value::

    (int | float) a = 4;

    return a.case(
        int i: i / 2,
        float f: f / 2.0f);

    a.case {
        int i:
            print(itoa(i));
        float f:
            print(ftoa(f));
    }

Members of a sumtype can be marked as "fail", enabling error return::

    (int | fail FileNotFound) foo() { return "test".readAll?.itoa; }

    int i = foo()?;

If foo returns a `FileNotFound`, it will be automatically returned at the `?`.

Struct
^^^^^^

A struct is a value type that combines various members and methods that operate on them::

    struct Foo
    {
        int a, b;
        int sum() { return this.a + b; }
    }

    Foo foo = Foo(2, 3);

    assert(foo.sum() == 5);

A method is a function defined in a struct (or class). It takes a reference to the struct value it is called
on as a hidden parameter called `this`.

Class
^^^^^

A class is a **reference type** that combines various members and methods that operate on them::

    class Foo
    {
        int a, b;
        this(this.a, this.b) { }
        int sum() { return this.a + b; }
    }

    Foo foo = new Foo(2, 3);

    assert(foo.sum() == 5);

Note that, as opposed to C++, the type `Foo` designates a reference to the class. It is impossible
to hold a class by value.

`this` is a special method without return value that designates the constructor of the class. When instantiating
a class with `new Class(args)`, `this(args)` is called.

The parameter `this.a` indicates that the argument is directly assigned to the member `a`, rather than passed to the method as a parameter.

Classes can be inherited with a subclass. An instance of the subclass can be implicitly converted to
the parent class. When a method is called on an instance, the function that runs is that of the
allocated class, not of the type of the reference::

    class Foo
    {
        int get() { return 5; }
    }

    class Bar : Foo
    {
        // "override" must be specified, to indicate
        // that a parent method is being redefined.
        override int get() { return 7; }
    }

    Foo foo = new Bar;
    assert(foo.get == 7);

Classes can also inherit from interfaces, which are like "thin classes" that can only contain methods.
In exchange, arbitrarily many interfaces can be inherited from::

    interface Foo
    {
        int get();
    }

    class Bar : Parent, Foo
    {
        override int get() { return 5; }
    }

    Foo foo = new Bar;
    assert(foo.get == 5);

The type of an object can be tested with the `instanceOf` property::

    nullable Bar bar = foo.instanceOf(Bar);

    if (Bar bar = foo.instanceOf(Bar)) { }

Return and parameter types follow `covariance and contravariance`_ on inheritance.

A class type may be qualified as `nullable`. In that case, the special value
`null` implicitly converts to a reference to the type. By default, class references are not
nullable::

    nullable Foo foo = null;
    assert(!foo);
    Foo bar = foo; // errors

As a special treat, the `case` expression allows treating a nullable class as a sumtype
of a non-nullable class and `null`::

    nullable Foo foo;
    Foo bar = foo.case(null: return false);

Symbol Identifier
^^^^^^^^^^^^^^^^^

A symbol identifier takes the form `:name`.

It is both a type and an expression. The type `:name` has one value, which is also `:name`.

This feature can be used to "type-tag" entries in sumtypes, to differentiate identically
typed entries, such as `(:centimeters, int | :meters, int)`.

It is also used to construct "value-less" sumtype entries, such as `(int | :none)`.

`typeof`
^^^^^^^^

Given an expression, the type of the expression can be used as a type with `typeof`::

    typeof(a + b) sum = a + b

Since `auto` exists, this is mostly used for return and parameter types.

.. _covariance and contravariance: https://en.wikipedia.org/wiki/Covariance_and_contravariance_(computer_science)

Unittest
--------

Unittest blocks will be compiled and run when the compiler is called with `-unittest`::

    int sum(int a, int b) { return a + b; }

    unittest
    {
        assert(sum(2, 3) == 5);
    }

Templates
---------

A template is a wrapper around a declaration that allows parameterizing it.
The syntax is::

    template max(T) {
        T max(T first, T second) {
            if (first > second) return first;
            return second;
        }
    }

Here, `T` is the "template parameter".

The symbol in the template must be *eponymous*, ie. have the same name as the template. To call it,
instantiate the template: `max!int(2, 3)` or `max!float(2.5, 3)`. Here, `max!int` is "the function `max`
in the version of the template `max` where `T` is `int`."

Multiple parameters are passed in parentheses: `templ!(int, float)`.

If the template is called directly, the types of the parameters will be used as template
parameters. This behavior is a placeholder.

Ranges
------

If a type `T` has the properties `bool empty`, `T next` and `E front`, then it is called a "range over `E`".

Arrays are an example of such.

Another example is range expressions: `from .. to`.

If you define these properties in a data type, you can use it as the source of a loop.

Lambdas
-------

A lambda is a templated nested function reference. They can be assigned to a value. When called, they
are implicitly instantiated.

Example::

    int a = 5;
    auto add = b => a + b;
    assert(add(2) == 7);

Every lambda has a unique type. Because of this, they cannot be stored in data structures.
Their primary purpose is being passed to templated functions::

    auto a = (0 .. 10).filter(a => a & 1 == 0).map(a => a / 2).array;

    assert(a == [0, 1, 2, 3, 4]);

Macros
------

.. note::
    For this feature, compiler knowledge is required!

When `macro(function)` is called, `function` is loaded into the compiler and executed with a macro state
parameter. This allows modifying the macro state of the compiler to add a macro class instance.
Macro classes can extend the compiler with new functionality using a set of hooks:

- calls: `a(b, c)`
- expressions: `2 ★ 2`
- properties: `a.b<property goes here>`
- statements: `macroThing;`
- imports: `import github("http://github.com/neat-lang/example").module;`

Look at `std.macro.*` for examples.

The entire compiler is available for importing and reuse in macros. However, it is recommended
to limit yourself to the functionality in `neat.base`. This will also keep compile times down.
