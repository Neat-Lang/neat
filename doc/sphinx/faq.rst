.. _faq:

.. |br| raw:: html

   <br />

Frequently Asked Questions
==========================

* Q: What's all this then?
* A: Neat is a C-like statically-typed native compiled language with reference counting. If you already know D_, you can think of it as a "D-like", or "D1 with macros."
* Q: Okay but why though.
* A: D is an amazing, wonderful language, and I love it a lot. Unfortunately, it's also terrible,
  hacky and broken. "Maybe if I make my own, it will be less hacky and broken," I thought, because
  apparently I lack pattern recognition. |br|
  At any rate, it does have some things D doesn't, such as named arguments, string literals, reasonable lambdas,
  oh yeah, and *macros.*
* Q: That's a lot of syntax features though, I hear syntax doesn't matter.
* A: Syntax totally matters! Pretty syntax makes code much easier to read and understand, which I am told is important.
* Q: Okay, so why should I use it?
* A: You probably shouldn't. |br|
  Neat is in serious alpha. You can expect the compiler to break in any medium sized project. The standard
  library is almost entirely nonexistent.
  This project is not ready for any sort of production use.
  However, if you want to have fun with a C-like language, and maybe learn a bit about more high-level
  programming idioms than C usually allows for, come try it out.
* Q: D has a GC. Why do you use automatic reference counting instead?
* A: People have told the D community for decades that the GC was a dealbreaker. |br|
  I don't think this is actually *true*, objectively, and certainly writing an ARC implementation has given me
  a whole new level of appreciation for the crazy amount of effort that having a GC saves you, and also I'm pretty
  sure now that Walter was actually correct about GC being faster, barring a lot more optimization to my
  ARC code - but still. Neat is a reaction to D, and D has spent decades apologizing for and trying to mitigate
  its garbage collector. By going with reference counting, I'm hoping to start out on a better foot with the
  C/C++ people from the start.
* Q: Why should I use your language *instead of C*?
* A: Like D, Neat is born of the view that "C is great, but it's also trash." There's a lot of things in C
  that are the way they are because that's the reality of the processor, but there's also a lot of things,
  like zero terminated arrays, the type syntax, includes, the underpowered typesystem, that are just
  borne from a lack of experience with language design. Neat doesn't follow C's syntax to the letter, but it
  certainly views it as a solid place to start from. At the same time, it corrects certain insanities like the
  function pointer syntax (`int function(int) foo`), modules instead of includes, true macros instead
  of text replacement, a rich built-in typesystem, including length-aware arrays (`int[]`), hashmaps
  (`int[string]`), nested functions, struct methods, classes and templates. |br|
  If you like C's sparsity, Neat will probably overload you. However, if you like C's simplicity and
  lack of compiler magic, you should find Neat similarly straightforward, since every feature can be
  easily described in terms of simpler primitives. Neat, like D, is a "C and more" language.
* Q: Why should I use your language *instead of C++*?
* A: I admit it: I don't understand why people voluntarily use C++. |br|
  It's slow to compile, every domain of its design has its own special rules, and for the past thirty
  years they've been gluing on parts and finding new uses for those parts and then gluing on more parts
  that fit with the new way to use them, it has all the insanity of C and it keeps adding more that
  *never ever gets fixed*. |br|
  Use C++ if you need to interact with the existing ecosystem, I guess.
  Use Neat if you want a language that you can actually, fully understand.
* Q: Why should I use your language *instead of D*?
* A: D has a lot of compiler magic that I think is, in retrospect, questionable.
  Compile-time functions as an extension of constant folding, lambdas as template parameters, can
  all be done better. Furthermore, the slow improvement process combined with the lack of macros
  holds D back as a testbed for cool/cute new language features. |br|
  Neat is not beholden to decades of existing code and can thus iterate faster. Also, even though
  Walter Bright is a way better programmer than I am, I think Neat's compiler has some architectural
  choices that will save it grief in the long run, such as using immutable data structures, or eschewing
  CTFE for staged compilation, ie. compiling a part of the program and loading it back in as a macro.
  While Neat is at the moment far slower than D to compile, I believe that the design gives it more
  avenues for parallelization and its template implementation should be more efficient at scale.
  However, right now and for the foreseeable future, D is definitely a better language. |br|
  So I guess come and try out Neat if you wanna play with some features like
  lambda values or format strings to see how they work in practice.

Project Layout
==============

* Q: What's up with `bootstrap.sh`?
* A: Neat was self-hosting from an early point on, and features were usually immediately
  used in the compiler.
  To make this easier, each version of Neat depends on a previous git commit that can build it.
  These commits are listed in `bootstrap.sh`: each commit is checked out and built with the previous version,
  all the way back to the D-based initial bootstrap version.
  Note that while this way, you can build a Neat compiler "from nothing", this is exceedingly slow,
  up to several hours. It is strongly recommended to download tagged builds from Github.
  However, every bootstrap build is cached, so successive calls to `./bootstrap.sh` should be
  reasonably fast.

.. _D: https://www.dlang.org/
