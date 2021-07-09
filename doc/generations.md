# \_\_GENERATION\_\_ and bootstrapping

Any self-hosting static-typed compiled language with macros in the source tree faces a problem.

Macros need access to the compiler source code in order to be API compatible
with the compiler they're loaded into. But the compiler source changes
in the course of development. So we're looking at at least two build steps:

- old compiler builds stage1 compiler with new source but old API
- stage1 compiler builds stage2 compiler with new source and new API.

Neat has several parts that make this process more manageable.

## Packages

First, every module exists inside a package. So neat.base can exist both in
package "compiler" and package "stage1", allowing macros to reference the
specific version for the API of the compiler currently running.

The package of the running compiler is called "compiler".

However, that alone would not be enough. Because the mangling of symbols
involves packages, and the mangling of symbols must stay stable for the
same source file during a build (because otherwise dynamic casts will break),
we **cannot** for instance build the new compiler as package "stage1" and then
rename it to "compiler" to build stage2.

## \_\_GENERATION\_\_

There is a global variable, `__GENERATION__`, that counts up by one every time
the compiler builds itself (with `rebuild.sh`). When we use the package
"compiler", the actual mangling is "compiler\_\_GENERATION\_\_". As such, the rebuild
script can use a commandline flag (`-print-generation`) to discover the current
"compiler" mangling, then just set the new source code to be built in package
"compiler$(\_\_GENERATION\_\_ + 1)". Which will be the correct mangling when
that source code gets defined as package "compiler" to build stage2.
