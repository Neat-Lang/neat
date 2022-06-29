.. highlight:: d

The Neat Language
=================

Neat is a C-like statically-typed native compiled language with automated reference counting, OOP and macros.
This is its documentation.

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
        auto text = cast(string) readFile(args[1]);

.. toctree::
   :maxdepth: 2
   :caption: Contents:

   getstarted
   intro
   manual
   std
