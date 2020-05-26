module backend.types;

import boilerplate;

interface BackendType
{
}

class BackendVoidType : BackendType { }

class BackendCharType : BackendType { }

class BackendIntType : BackendType { }

class BackendLongType : BackendType { }

class BackendPointerType : BackendType
{
    BackendType target;

    mixin(GenerateThis);
}

class BackendStructType : BackendType
{
    BackendType[] members;

    mixin(GenerateThis);
}

class BackendFunctionPointerType : BackendType
{
    BackendType returnType;

    BackendType[] argumentTypes;

    mixin(GenerateThis);
}
