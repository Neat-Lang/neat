module backend.types;

import boilerplate;
import std.format;
import std.typecons : Tuple;

interface BackendType
{
    int size(Platform platform) const;
    int alignment(Platform platform) const;
}

interface Platform
{
    int nativeWordSize();
}

class BackendVoidType : BackendType {
    override string toString() const { return "void"; }
    override int size(Platform) const { return 0; }
    override int alignment(Platform) const { return 1; }
}

class BackendCharType : BackendType {
    override string toString() const { return "char"; }
    override int size(Platform) const { return 1; }
    override int alignment(Platform) const { return 1; }
}

class BackendIntType : BackendType {
    override string toString() const { return "int"; }
    override int size(Platform) const { return 4; }
    override int alignment(Platform) const { return 4; }
}

class BackendLongType : BackendType {
    override string toString() const { return "long"; }
    override int size(Platform) const { return 8; }
    override int alignment(Platform) const { return 8; }
}

BackendType backendWordType(Platform platform)
{
    switch (platform.nativeWordSize) {
        case 4: return new BackendIntType;
        case 8: return new BackendLongType;
        default: assert(false, format!"Unknown word size %s"(platform.nativeWordSize));
    }
}

class BackendPointerType : BackendType
{
    BackendType target;

    override string toString() const { return format!"%s*"(target); }
    override int size(Platform platform) const { return platform.nativeWordSize; }
    override int alignment(Platform platform) const { return platform.nativeWordSize; }

    mixin(GenerateThis);
}

class BackendStructType : BackendType
{
    BackendType[] members;

    override string toString() const { return format!"{ %(%s, %) }"(members); }

    override int size(Platform platform) const {
        auto pair = calcPrefix(platform, this.members.length);

        return pair.size.roundToNext(pair.alignment);
    }

    override int alignment(Platform platform) const {
        return calcPrefix(platform, this.members.length).alignment;
    }

    int offsetOf(Platform platform, size_t memberIndex) const {
        return calcPrefix(platform, memberIndex).size;
    }

    Tuple!(int, "size", int, "alignment") calcPrefix(Platform platform, size_t memberIndex) const
    {
        import std.algorithm : max;

        int structSize = 0;
        int structAlign = 1;
        foreach (member; members[0 .. memberIndex]) {
            int alignment = member.alignment(platform);
            int size = member.size(platform);
            // round to next <alignment>
            structSize = structSize.roundToNext(alignment);
            structSize += size;
            structAlign = max(structAlign, alignment);
        }
        return typeof(return)(structSize, structAlign);
    }

    mixin(GenerateThis);
}

int roundToNext(int value, int size)
{
    value += size - 1;
    value -= value % size;
    return value;
}

class BackendFunctionPointerType : BackendType
{
    BackendType returnType;

    BackendType[] argumentTypes;

    override string toString() const { return format!"%s(%(%s, %))"(returnType, argumentTypes); }
    override int size(Platform platform) const { return platform.nativeWordSize; }
    override int alignment(Platform platform) const { return platform.nativeWordSize; }

    mixin(GenerateThis);
}
