module backend.platform;

import backend.backend;
import backend.types;
import std.algorithm;

class DefaultPlatform : Platform
{
    override int nativeWordSize()
    {
        static assert(size_t.sizeof == 8);
        return 8;
    }
}
