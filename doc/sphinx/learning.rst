.. _learning:

Learning Neat
=============

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

Neat does not use includes but packages. A package is a folder associated with a name::

    $ # -P<name>:<folder>[:<dependency>[,<dependency]*]
    $ neat -Proot:src src/hello/world.nt

Packages cannot access modules in other packages. To allow a package access, explicitly
list the packages that it has access to::

    $ neat -Proot:src:dep1,dep2 -Pdep1:include/dep1 -Pdep2:include/dep2

This allows the modules in `src/` to import the modules in `dep1` and `dep2`.
Because depdencies are explicitly listed, accidental import of modules from
an unrelated package is impossible.

Module-Level Statements
-----------------------

Import
^^^^^^

A module can import another module::

    module hello.world;

    import std.stdio;

Import is non-transitive, ie. symbols from modules imported by `std.stdio` are invisible.

Symbols can be imported by name: `import std.stdio : print;`.

Declaration
^^^^^^^^^^^

Structs, classes, templates and functions can be declared by name.
Every declaration can be marked as `public` or `private`; they are `public` by default.
Private declarations cannot be seen when the module is imported.

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
`a || b`  Boolean "or"   0
`a && b`  Boolean "and"  1
`a <= b`  Comparison     2
`a .. b`  Range          3
`a << b`  Left shift     4
`a >> b`  Right shift    4
`a + b`   Addition       5
`a - b`   Subtraction    5
`a ~ b`   Concatenation  5
`a * b`   Multiplication 6
`a / b`   Division       6
`a | b`   Bitwise "or"   7
`a ^ b`   Bitwise "xor"  8
`a & b`   Bitwise "and"  9
========= ============== ====

Boolean "or" and "and" are short-circuiting. Comparison operators are `>`, `==`, `<`, `>=`, `<=`, and `!=`.
Higher-ranked operators take precedence over lower-ranked, with boolean operators being the loosest.

Note that the placement of bitwise operators diverges from C's order.
This is because C's order is stupid^W a legacy holdover from before it had boolean operators.

Operator precedence can be clarified using parentheses: `2 * (3 + 4)` instead of `2 * 3 + 4`.

Functions
---------

A function is a series of statements operating on a list of parameters, culminating in a return value::

    ReturnType functionName(ParameterType parameterName, ParameterType2 parameterName2) {
        statement;
        statement;
        statement;
        return 5;
    }
    ...
        ReturnType ret = functionName(1, foo);

When a function is called with `name(arg, arg)`, the arguments are passed to the parameters and
control passes to the function. The statements of the function are then executed, until control
returns to the caller.

Call
^^^^

A function, class method or struct method can be called with a comma-separated list of arguments::

    print("Hello World");

    double d = sin(0.0);

    class.method();

When a function does not have any parameters, the empty parents can be left out, and the function will be
called implicitly::

    doWork;

This also allows struct or class methods that look like properties.

Nested functions
^^^^^^^^^^^^^^^^

Functions may be nested inside other functions. They remain valid while the surrounding function is running,
and can access variables and parameters of the containing function.

main
^^^^

Every program must have a function with this signature::

    void main(string[] args) {
    }

This function will be called when the program is run.

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

Block statement
^^^^^^^^^^^^^^^

Multiple statements can be combined into one::

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

Note that only mutable (`mut`) values or parameters can be reassigned.

If test
^^^^^^^

If a condition is true, execute one statement, else the other::

    if (2 == 2)
        print("4");
    else {
        print("sanity has deserted us");
    }

The condition of the `if` statement may be a variable declaration or variable extraction.
In that case, the condition is true if the value of the variable is true, or if the
extraction succeeds. The variable will only be visible inside the `if` block::

    if (nullable Foo foo = getFoo()) {
        // do foo things here
    }
    (int | Error) bar;
    if (int i <- bar) { }

If the condition extracts a type, then if the condition fails, execution continues after the `if` -
the other types are not implicitly returned!

While loop
^^^^^^^^^^

While a condition is true, execute a statement::

    mut int i = 0;
    while (i < 10) { i += 1; }

For loop
^^^^^^^^

A range expression can be looped over::

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

`[2]` is an array of ints, allocated on the heap.

`array ~ array` is the concatenation of two arrays.

Appending to an array in a loop will follow a doubling strategy. It should be reasonably efficient.

`array[2]` is the third element (base-0) of the array.

Tuple
^^^^^

`(int, float)` is a tuple with two member types, `int` and `float`. Each member can have an independent value.

`(2, 3.0f)` is an expression of type `(int, float)`.

`tuple[0]` is the first member of the tuple. The index value must be an int literal.

Sum type
^^^^^^^^

`(int | float)` is either an int or a float value::

    (int | float) a = 4;

    return a.case(
        int i: i / 2,
        float f: f / 2.0f);

    a.case {
        int i: {
            print(itoa(i));
        }
        float f: print(ftoa(f));
    }

    if (int i <- a) {
        print(i);
    }

Members of a sumtype can be marked as "fail", enabling error return::

    (int | fail FileNotFound) foo() { return "test".readAll.itoa; }

    // if foo returns a FileNotFound, it will be implicitly returned.
    int i <- foo();

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
        // "override" must be specified, to indicate that a parent method is being redefined
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

TODO!

Ranges
------

TODO!

Lambdas
-------

TODO!

Macros
------
TODO!
