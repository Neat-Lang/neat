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
    BackendFunction define(string name, BackendType ret, BackendType[] args);
}

interface BackendType
{
}

interface BackendFunction
{
    int blockIndex();
    Reg arg(int index);
    Reg call(string name, Reg[] args);
    Reg literal(int value);
    Reg alloca(BackendType type);
    Reg fieldOffset(BackendType structType, Reg structBase, int member);
    void store(BackendType dataType, Reg target, Reg value);
    Reg load(BackendType dataType, Reg target);
    // block enders
    void ret(Reg);
    TestBranchRecord testBranch(Reg test);
}

// helper to allow delayed jump resolution
interface TestBranchRecord
{
    void resolveThen(int index);
    void resolveElse(int index);
}
