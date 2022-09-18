.. _getstarted:
.. highlight:: d

Getting Started
===============

The Neat compiler is at the moment only tested on 64-bit x86 Linux. However, it *should* work on other 64-bit platforms,
and be able to be ported to 32-bit platforms with little effort.

There are two available versions, depending on backend: LLVM 14 or GCC based. Note that both versions will require gcc
to be installed for certain macros to work. Also, while the LLVM backend release may use the gcc backend, the gcc backend
release cannot use LLVM, because it will not be built against it.

The primary question, thus, is which backend you expect to use "by default." However, to my knowledge, aside the inherent
differences of LLVM's and gcc's backend, both Neat backends are equally capable. The choice is thus largely down to personal preference.

The installation instructions assume, and are tested with, Ubuntu 22.04. Take required steps as equivalent for your system.

Install with LLVM
-----------------

1. Install required packages::

    apt-get install xz-utils wget gcc llvm-14-dev clang-14

2. Download the latest release from https://github.com/neat-lang/neat/releases

3. Unpack the archive::

    tar xf neat-v*-llvm.tar.xz
    cd neat-v*-llvm

4. Build the compiler::

    ./build.sh

5. Symlink the compiler somewhere that's in your path::

    mkdir -p "$HOME"/.local/bin
    ln -s "$PWD"/neat "$HOME"/.local/bin/neat

5. Test the compiler::

    cat > hello.nt <<EOF
    module hello;
    import std.stdio;
    void main() { print("Hello World"); }
    EOF
    neat hello.nt && ./hello

If that printed "Hello World", your Neat compiler is now ready for use!

Install with GCC
----------------

1. Install required packages::

    apt-get install xz-utils wget gcc

2. Download the latest release from https://github.com/neat-lang/neat/releases

3. Unpack the archive::

    tar xf neat-v*-gcc.tar.xz
    cd neat-v*-gcc

4. Build the compiler::

    ./build.sh

5. Symlink the compiler somewhere that's in your path::

    mkdir -p "$HOME"/.local/bin
    ln -s "$PWD"/neat "$HOME"/.local/bin/neat

5. Test the compiler::

    cat > hello.nt <<EOF
    module hello;
    import std.stdio;
    void main() { print("Hello World"); }
    EOF
    neat hello.nt && ./hello

If that printed "Hello World", your Neat compiler is now ready for use!

Start a Project
---------------

Binary
^^^^^^

Neat comes with a built-in package manager. To configure it, create a file `package.json` in the project's base folder::

    {
        "source": "src",
        "type": "binary",
        "binary": "progname",
        "main": "src/main.nt",
        "dependencies": {
            "package": "*"
        },
        "sources": {
            "package": "https://github.com/example/package"
        }
    }

Run `neat build` in a folder that contains a `package.json` with type `binary`, and Neat will attempt to build a binary.

Library
^^^^^^^

The format for library repos is significantly simpler::

    {
        "source": "src",
        "type": "library"
    }

Keys
^^^^

- `source`: The default source folder.
- `type`: `binary` or `library`. Note that all Neat packages are effectively source libraries.
- `binary`: The executable that will be generated.
- `main`: The name of the file that contains the main function. This does nothing at the moment, but will be important when `neat unittest` is added.
- `compilerVersion`: The version of the compiler to build with. When the installed compiler does not match this version, the required compiler version (gcc backend) will be built and executed.
- `dependencies`: A map of dependencies and their versions.
- `sources`: A map of dependencies to Git Remote URLs.

Version Specification
^^^^^^^^^^^^^^^^^^^^^

Neat implements `semantic versioning <https://semver.org/>`_. The required version of a package can be specified in the following ways:

- `*`: Any version will do.
- `^x.y.z`: Any version *semver-compatible* with `x.y.z` will do.
    That is, it must be equal on `x` and greater or equal on `y.z`.
- `>=x.y.z`: Any version newer or equal to `x.y.z` will do.
- `<=x.y.z`: etc.
- `>x.y.z`: etc.
- `<x.y.z`: etc.
- `=x.y.z`: etc.

Version resolution proceeds recursively with backtracking. A version is a tag on the Git source of the format `vx.y.z`, for instance `v1.0.3`.

On first run, `neat build` writes the recursive selected package versions in a file `package-lock.json`. This file should be committed to ensure reproducible builds; however, when recursing into packages, the recursive package-lock files are ignored.

Good and Bad Neat
-----------------

With D, you can write code in many styles, and while programs off the "happy path" will have problems, they will generally
still work. As Neat is heavily alpha, code that diverges too far from my own style will probably explode.

Keep in mind that if you're unsure, you can always just ask me. And if it seems like there isn't a way to do something, it's very plausible
that there isn't, just because it's something I haven't needed yet. And keep in mind: if something randomly doesn't work, it's
very plausibly a compiler bug.

Pure functions are Just Better
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

If runtime is not absolutely critical, try to arrange your code so that it never mutates parameters. When you need to
mutate something, encapsulate it in a class. (`final class` method calls are as good as direct function calls.) Alternately,
take old state as parameters and return new state as return values. (This isn't just good Neat, it's good code in general.)
Neat has several features to support this, such as sumtypes and tuples, to allow defining complex returned data structures.

Structs are values, classes are owners
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

Generally speaking, you should use structs (and the other built-in data types) for the "domain" layer of your code,
ie. values that are passed to a function and returned from a function. Classes should be reserved for types that own
data, mutate state and react to events. If it involves a change in the state of your application, a class makes sense.

(But don't take this as gospel too much: classes are also just reference types, and useful if you need a reference for
whatever reason.)

Don't microoptimize
^^^^^^^^^^^^^^^^^^^

The advice usually goes to not microoptimize prematurely. As Neat is alpha, I would make the advice stronger:
don't microoptimize at all. If you write some incredibly microoptimized code and it doesn't work, and you submit
that as a bug report, I'm just as likely to make that entire idiom forbidden. Remember: many things compile in Neat today
that *shouldn't*, simply because I haven't thought to add checks for them yet. If you write code in a straightforward
fashion, I'll be much more amenable to a bug report to make it fast. (So long as it doesn't unduly complicate the compiler.)

Don't use pointers
^^^^^^^^^^^^^^^^^^

Pointers are in the language for one thing and one thing only: interacting with C APIs. They do **not** participate in
reference counting. If you absolutely have to use pointers, make sure that the reference you are passing a pointer to
outlives the pointer value.

How do you modify state from a called function? Pass a "natural" reference type, ie. classes or arrays. Or just
return the new value.

Closures are dynamic
^^^^^^^^^^^^^^^^^^^^

There is zero escape analysis. There is no closure allocation. Also, delegates don't participate in reference counting.
As with pointers, if you pass a closure to a function, whether as a delegate or as a lambda, ensure that the function's
use of that closure does not outlive the calling stack frame.

If you want to implement something like a timer task, keep in mind that subclasses can be declared inside a function,
and just subclass `TimerTask` locally.

`neat.base` is the key to macros
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

The compiler is not as fast as I'd wish. As such, while you can in principle access every module from a macro,
limiting yourself to `neat.base` or `neat.util` will keep your macros reasonably fast to load. Similarly, if you
read `neat.base`, it will give you a good introduction to the data structures used by the rest of the compiler.

Neat is not great, Neat is not final
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

There were several decisions made during design that have come back to hamper me. While the language *is* broadly
where I wanted it starting out, every aspect of it is amenable to modification. Don't assume that because something
is in the compiler, that it is deliberate and optimal. Feel free to experiment with a local copy, and as usual:

Patches welcome!
