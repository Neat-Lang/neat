module backend.backend;

import backend.types;
import boilerplate;

alias Reg = int;

interface Backend
{
    BackendModule createModule(Platform platform);
}

interface Platform
{
    int nativeWordSize();
    int size(const BackendType type);
    int offsetOf(const BackendStructType type, int member);
}

interface BackendModule
{
    BackendFunction define(string name, BackendType ret, BackendType[] args);
    Backend backend();
    Platform platform();
}

interface BackendFunction
{
    int blockIndex();
    Reg arg(int index);
    Reg call(BackendType type, string name, Reg[] args);
    Reg intLiteral(int value);
    Reg stringLiteral(string text);
    Reg voidLiteral();
    Reg alloca(BackendType type);
    /// ops: + - * / % & | ^ < > <= >= ==
    Reg binop(string op, Reg left, Reg right);
    Reg field(BackendType structType, Reg structValue, int member);
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
