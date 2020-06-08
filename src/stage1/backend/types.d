module backend.types;

import boilerplate;
import std.format;

interface BackendType
{
    int size(Platform platform) const;
}

interface Platform
{
    int nativeWordSize();
}

class BackendVoidType : BackendType {
    override string toString() const { return "void"; }
    override int size(Platform) const { return 0; }
}

class BackendCharType : BackendType {
    override string toString() const { return "char"; }
    override int size(Platform) const { return 1; }
}

class BackendIntType : BackendType {
    override string toString() const { return "int"; }
    override int size(Platform) const { return 4; }
}

class BackendLongType : BackendType {
    override string toString() const { return "long"; }
    override int size(Platform) const { return 8; }
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

    mixin(GenerateThis);
}

class BackendStructType : BackendType
{
    BackendType[] members;

    override string toString() const { return format!"{ %(%s, %) }"(members); }

    override int size(Platform platform) const {
        // TODO alignment
        int sum;
        foreach (member; members) sum += member.size(platform);
        return sum;
    }

    int offsetOf(Platform platform, int member)
    {
        // TODO alignment
        int sum;
        foreach (structMember; members[0 .. member]) sum += structMember.size(platform);
        return sum;
    }

    mixin(GenerateThis);
}

class BackendFunctionPointerType : BackendType
{
    BackendType returnType;

    BackendType[] argumentTypes;

    override string toString() const { return format!"%s(%(%s, %))"(returnType, argumentTypes); }

    override int size(Platform platform) const { return platform.nativeWordSize; }

    mixin(GenerateThis);
}
