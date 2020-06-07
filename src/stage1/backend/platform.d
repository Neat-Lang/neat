module backend.platform;

import backend.backend;
import backend.types;
import std.algorithm;

// size_t
BackendType sizeType(Platform platform)
{
    switch (platform.nativeWordSize)
    {
        case 4: return new BackendIntType;
        case 8: return new BackendLongType;
        default: assert(false);
    }
}

class DefaultPlatform : Platform
{
    override int nativeWordSize()
    {
        static assert(size_t.sizeof == 8);
        return 8;
    }
}
