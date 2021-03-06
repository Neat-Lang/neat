.. _getstarted:
.. highlight:: d

Getting Started
===============

The Neat compiler is at the moment only tested on 64-bit x86 Linux. However, it *should* work on other 64-bit platforms, and be able to be ported to 32-bit platforms with little effort.

There are two available versions, depending on backend: LLVM 12 or GCC based. Note that both versions will require gcc to be installed for certain macros to work. Also, while the LLVM backend release may use the gcc backend, the gcc backend release cannot use LLVM, because it will not be built against it.

The primary question, thus, is which backend you expect to use "by default." However, to my knowledge, aside the inherent differences of LLVM's and gcc's backend, both Neat backends are equally capable. The choice is thus largely down to personal preference.

The installation instructions assume, and are tested with, Ubuntu 20.04. Take required steps as equivalent for your system.

Neat is distributed as C file dumps generated by the C backend.

Install with LLVM
-----------------

1. Install required packages::

    apt-get install unzip gcc llvm-12-dev clang-12

2. Download the latest release from https://github.com/neat-lang/neat/releases

3. Unpack the archive::

    unzip neat-v*-llvm.zip
    cd neat

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

    apt-get install unzip gcc

2. Download the latest release from https://github.com/neat-lang/neat/releases

3. Unpack the archive::

    unzip neat-v*-gcc.zip
    cd neat

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
        "compilerVersion": "0.1.2",
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
