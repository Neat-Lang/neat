## Goal

There is a specification for a minimal bytecode suitable for being compiled or interpreted.

The bytecode contains an 'eval()' operation to take an area of memory that contains bytecode for a function,
and return a function pointer that when called evaluates that function.

The bootstrap compiler is stored in this bytecode. When run, it compiles the rest of the compiler,
and uses the eval() operation to complete itself. Then it compiles whatever userland code you give it,
which has the same opportunity to load functions back into the compiler.

The bytecode may be compiled to native code. During this, eval() may either be replaced with an interpreter
library call, or a helper that generates fragmentary native code from the passed bytecode and dlopens it back.

## Steps

1. Initial bootstrap compiler and interpreter
2. Self-hosting
3. Extensible/Minimized

### Initial bootstrap compiler

The language may be initially compiled to bytecode by a first-stage bootstrap compiler. The bootstrap compiler
already produces bytecode. In this stage, enough functionality must be added to the language and BC to support
rewriting it in itself.

### Self-hosting

The goal of this stage is to port the language from its bootstrap language into itself. After this stage is done,
interpreting the language's bytecode should produce an identical copy of its bytecode.

### Extensible/Minimized

With the use of a readback operation, language primitives may now again be actively removed from the bc set. The bc
compiler only requires enough functionality to load the rest of the language. For instance, loops may be replaced
here with recursion. After this is done, the compiler should consist of two stages: stage1 which must be available in
bytecode form to run the compiler at all, and stage2 which may be kept in pure source form and will never be compiled
except as a side-effect of eval().
