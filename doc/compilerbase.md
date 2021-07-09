# The CompilerBase Class

## Introduction

In order to avoid circular compiler dependencies, `neat.base` contains a
`CompilerBase` class that is implemented in `main` and passed through
to all compiler calls.

## Rationale

Normally, the compiler classes would be divided into cleanly separated modules.
However, compilers are annoyingly interconnected. When parsing, most more
involved parsed constructs will require looping back into statement/expression
parsing. Similarly, AST and runtime classes are usually expressed in terms of
other classes, which again introduces cycles. For example, the array feature requires
generating an array-append function that loops over source elements, which pulls
in functions, scopes, loops, etc.

To resolve this, the compiler defines `CompilerBase` as a generic interface to the
rest of the compiler. This class allows parsing source, creating AST trees, or
creating IR trees. This works because usually when we're creating an IR or AST
object, we don't particularly care about it for its members or methods, but just use
it to represent a certain behavioral meaning in the program tree. So we don't care
that an astIndexAccess call creates an ASTIndexAccess class, so much as an ASTSymbol
class that happens to represent an index access.

## Self-Hosting

In the context of macros called inside the compiler, the existence of `CompilerBase`
leads to a snag.

Since the macro will be pulling in the original compiler's version of `CompilerBase`,
we cannot use new `Compiler` features immediately. Instead, we need to create a
commit with the extended `CompilerBase`, then add that commit to the bootstrap script
and use it in a following commit.

In order to change behavior, a more complicated dance is required. Each line is one commit:

- Introduce a new function `<name>2` with the new behavior
- Use the new function in all code, switch the old function to the new semantics
- Use the old function again.
