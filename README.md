# Neat

Neat is a compiler for NeatLang, a D1-like language with macros.

# Documentation

- TODO LOL
- [Compiler Internals](./doc/index.md)
- [The testcases](./test/runnable/)
- [The demo(s)](./demos/)

# License

Special case first:

- `std.sha256` is excluded from the following section, being licensed BSD-3-Clause. Thank you Olivier Gay and
Con Kolivas. Any copyright claims arising from my port are likewise BSD-3-Clause.

---

cx is licensed under the [GPLv3](./LICENSE).

At this time, I strongly recommend only using cx for private (non-distributed) or GPL projects.

There is no linking or classpath exemption! If you distribute a binary produced with the compiler, it may qualify as a
derived work and fall under the GPLv3!

This is because as a macro compiler, the entire compiler source is part of the standard library.

So if there was an exemption for standard library modules, the effect would be to render the GPL license meaningless,
as you could easily build a copy of the compiler and distribute it under any license.

Conversely, if the compiler source was included in the GPL without exemption, you could not use any macros in
closed-source projects.

So for the time being, if you want to use cx in a commercial project, please contact me
(http://github.com/FeepingCreature/) for a license agreement.

Or if you have an idea for how to thread the needle between GPL licensing and BSD for a project like this,
please open an issue.

Because the ultimate license of this project is not settled, for the time being, if you open a pull request, be
aware I will ask you to assign me the copyright for your changes.
