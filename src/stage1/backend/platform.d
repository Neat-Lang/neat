module backend.platform;

import backend.types;
import std.algorithm;

interface Platform
{
    int nativeWordSize();
    int size(const BackendType type);
    int offsetOf(const BackendStructType type, int member);
}

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

    override int size(const BackendType type)
    {
        if (auto structType = cast(BackendStructType) type)
        {
            // TODO alignment
            int sum;
            foreach (member; structType.members) sum += size(member);
            return sum;
        }
        if (cast(BackendVoidType) type) return 0;
        if (cast(BackendCharType) type) return 1;
        if (cast(BackendIntType) type) return 4;
        if (cast(BackendLongType) type) return 8;
        if (cast(BackendPointerType) type) return nativeWordSize;
        if (cast(BackendFunctionPointerType) type) return nativeWordSize;

        import std.format : format;

        assert(false, format!"TODO %s"(type));
    }

    override int offsetOf(const BackendStructType structType, int member)
    {
        // TODO alignment
        int sum;
        foreach (structMember; structType.members[0 .. member]) sum += size(structMember);
        return sum;
    }
}
