.. highlight:: d

The Neat Language
=================

Neat is a C-like statically-typed native compiled language with automated reference counting, OOP and macros.
Its syntax is heavily "inspired by" D.

Have some example code! Here's a program that prints the longest line in a file::

    module longestline;

    macro import std.macro.listcomprehension;

    import std.file;
    import std.stdio;
    import std.string;

    void main(string[] args) {
        auto text = readText(args[1]);
        string longestLine = [
            argmax(line.strip.length) line
            for line in text.split("\n")];
        print(longestLine);
    }
    ...
    $ neat longestline.nt
    ...
    $ ./longestline longestline.nt
    macro import std.macro.listcomprehension;

**Important notice**: Before you jump in, please read the section :ref:`getstarted:Good and Bad Neat`!

For **more examples,** see the `Demos <https://github.com/Neat-Lang/neat/tree/master/demos>`_ page.

Community
=========

- `Neat Language on Discord <https://discord.gg/QkUecKgUvS>`_
- `#neat on libera.chat <https://web.libera.chat/#neat>`_ (formerly Freenode).
- If you're trying out the language, drop by and say hi!
- `Github Discussions <https://github.com/Neat-Lang/neat/discussions>`_

Contents
========

.. toctree::
   :maxdepth: 2

   getstarted
   intro
   manual
   std
   Neat on Github 🔗 <https://github.com/neat-lang/neat/>
