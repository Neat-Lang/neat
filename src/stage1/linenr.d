module linenr;

import std.algorithm;
import std.format;
import std.range;

class LineNumberRegistry
{
    struct File
    {
        string name;

        string text;
    }
    File[] files;

    string at(string where)
    {
        foreach (file; files)
        {
            if (where.ptr >= file.text.ptr && where.ptr < file.text.ptr + file.text.length)
            {
                foreach (i, line; file.text.splitter("\n").enumerate)
                {
                    if (where.ptr >= line.ptr && where.ptr < line.ptr + line.length)
                    {
                        return format!"%s:%s:%s"(file.name, i + 1, where.ptr - line.ptr + 1);
                    }
                }
                assert(false);
            }
        }
        assert(false);
    }

    void register(string filename, string text)
    {
        files ~= File(filename, text);
    }
}

