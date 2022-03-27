.. _intro:

.. |br| raw:: html

   <br />

Introduction
============

What's all this then?
---------------------

Neat is a C-like statically-typed native compiled language with automated reference counting, OOP and macros.
If you already know D_, it's very similar to D1. But without a garbage collector. And with macros.

While different platforms are supported in theory, at the moment it **only works on Linux.**

Compared to D, it has some upsides and some downsides. It's a lot younger and a lot less tested. It also compiles
a lot slower. (`Walter Bright`_ is an actual wizard.) However, it has native support for some things that are
cumbersome library constructs in D: sum types, tuples, named parameters, and format strings.
(Coming to D any year now!) It also comes with built-in package management support.

Also, you know. Macros.

.. note::
    I am aware that people who try Neat now are taking a big risk, as the language is still subject to massive change.
    To reduce this risk, **Neat contains a mechanism to download, build and execute older versions of the compiler**.
    If you pin the compiler version in your package.json, any future version of Neat that may be installed on your
    system will still build your project with the original version that you last used. This way, you have full
    control of the rate at which your project updates.

Why another new language?
-------------------------

The most important thing to me is that you should **have fun using the language**. The biggest innovation in
C-likes, Rust, is primarily built on not letting you do things. Nobody understands what the hell C++ is doing anymore,
it's approaching string theory levels of opaqueness. Go is specifically built on the premise that Google developers
are incompetent and must be kept away from any semblance of language power. D is a shining light of developer
empowerment, but *snip ten minutes of gripes with the project*. I believe that writing Neat should be easy and fun.
If you do something stupid, the compiler should tell you with a nice readable error, if you want to do it anyway,
the compiler should get out of your way. If you do things in the straightforward way, you should get straightforward
results. Alternately, if you want to prototype a new syntax or type approach, that should be easy too. A simple,
extensible, expressive core, predictable results, power but no magic. That's the idea.

Tell me more about Neat.
------------------------

Neat uses single class inheritance with multiple interfaces; classes are always
reference types, and are intended to control state mutation, whereas structs are by-value, plain old data,
cannot be inherited and are intended to describe state.

C style functions look as they do in C.
For high-level code, you can also opearte on ranges, which are data types that yield successive values.
This affords a style similar to functional programming at the function level.
This style is supported by lambda expressions and nested functions, creating pure computational
elements that are composable and testable.

There's a rich set of built-in types, including length-aware arrays, hashmaps, sumtypes and tuples.

Variables are immutable and unreferenceable by default, but can be easily marked as mutable.

Neat code is divided into modules; each module corresponds to one file, and can be non-transitively imported into
other modules.

For reusable code, Neat also has template support, though it's in the beginning stages. Sum types are reused for
error handling, using built-in syntax to easily propagate errors upcall.

Note that all of these are subject to change as the language develops. Neat is written in idiomatic Neat
and BSD-licensed. The code won't win any prizes as it stands, but I'm very much open to pull requests. If I've made
a stupid decision, everything can be fixed. :-)

A digression: why reference counting?
-------------------------------------

In a divergence from D, Neat uses reference counting as its memory management strategy. With automatic
lifetime tracking, this is mostly transparent to users. While the memory management
is in total more expensive than in D, the costs in memory and cleanup overhead are more predictable and evenly
distributed.

(Turns out that when he said that GC was in total faster, Walter Bright was right. Who could have predicted this.)

Also reference-counting memory management is vulnerable to reference cycles. At the moment, my advice to address
this is to avoid creating reference cycles.

So why am I going with reference counting if I know GC is better?

I've been in the D community for a good decade and a half. People keep telling us they don't like the GC.
They keep saying GC is a dealbreaker. They want predictable memory usage and cleanup times. Somehow, none of
this is ever an issue with C# and Java. Somehow, the fact that any memory allocator, including glibc's, can incur
arbitrary delays never matters. Well, fine! Fine. Whatever. I disagree with the choice, but as an offshoot of
an offshoot, I really can't afford alienating folks. I'm tired of arguing this point. Nobody has ever said that
reference counting was a dealbreaker. So reference counting it is.

Is Neat production ready?
-------------------------

No. It is not. It is *hilariously* not.

While every subsystem I really wanted for the language is in place, they're all somewhere between
90% and 10% built out. Hashmaps support int keys and string keys only. Overloading is not a thing. Vectors are in,
but not matrices. *Every part of the language* is like that. Any commit I make to a Neat project incurs one
to the compiler. (It used to be two.)

But it works. It runs, it can read source and compile it. And, you know, even now, some parts are pretty slick.

A note on security
------------------

Neat has no runtime limitations on macros. A macro can do anything that the compiler itself can do. As a result,
any package you include can run arbitrary code on your system. While this may seem unsafe, how often do you build
a binary and then not run it anyways? Meanwhile, any build system that lets dependencies add prebuild steps already
allows unrestricted code execution anyways. If you run a build farm, always run builds in VMs. As a private user,
just keep in mind that building a project is as good as running it, from a security perspective.

.. _D: https://www.dlang.org/
.. _Walter Bright: https://en.wikipedia.org/wiki/Walter_Bright
