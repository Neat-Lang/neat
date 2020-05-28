module backend.types;

import boilerplate;
import std.format;

interface BackendType
{
}

class BackendVoidType : BackendType {
    override string toString() const { return "void"; }
}

class BackendCharType : BackendType {
    override string toString() const { return "char"; }
}

class BackendIntType : BackendType {
    override string toString() const { return "int"; }
}

class BackendLongType : BackendType {
    override string toString() const { return "long"; }
}

class BackendPointerType : BackendType
{
    BackendType target;

    override string toString() const { return format!"%s*"(target); }

    mixin(GenerateThis);
}

class BackendStructType : BackendType
{
    BackendType[] members;

    override string toString() const { return format!"{ %(%s, %) }"(members); }

    mixin(GenerateThis);
}

class BackendFunctionPointerType : BackendType
{
    BackendType returnType;

    BackendType[] argumentTypes;

    override string toString() const { return format!"%s(%(%s, %))"(returnType, argumentTypes); }

    mixin(GenerateThis);
}
