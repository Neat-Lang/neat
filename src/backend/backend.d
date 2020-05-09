module backend.backend;

alias Reg = int;

interface Backend
{
    BackendModule createModule();
}

interface BackendModule
{
    BackendType intType();
    BackendType voidType();
    BackendType structType(BackendType[] types);
    BackendType pointerType(BackendType target);
    BackendType funcPointerType(BackendType ret, BackendType[] args);
    BackendFunction define(string name, BackendType ret, BackendType[] args);
}

interface BackendType
{
}

interface BackendFunction
{
    int blockIndex();
    Reg arg(int index);
    Reg call(BackendType type, string name, Reg[] args);
    Reg intLiteral(int value);
    Reg voidLiteral();
    Reg alloca(BackendType type);
    Reg fieldOffset(BackendType structType, Reg structBase, int member);
    void store(BackendType dataType, Reg target, Reg value);
    Reg load(BackendType dataType, Reg target);
    Reg getFuncPtr(string name);
    Reg callFuncPtr(BackendType type, Reg ptr, Reg[] args);
    // block enders
    void ret(Reg);
    BranchRecord branch();
    TestBranchRecord testBranch(Reg test);
}

/// helpers to allow delayed jump resolution
interface BranchRecord
{
    void resolve(int index);
}

/// ditto
interface TestBranchRecord
{
    void resolveThen(int index);
    void resolveElse(int index);
}
