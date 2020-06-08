module backend.backend;

import backend.types;
import boilerplate;

alias Reg = int;

interface Backend
{
    BackendModule createModule(Platform platform);
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
    Reg longLiteral(long value);
    Reg stringLiteral(string text);
    Reg voidLiteral();
    Reg alloca(BackendType type);
    /// ops: + - * / % & | ^ < > <= >= ==
    Reg binop(string op, int size, Reg left, Reg right);
    // fill with 0 <from> bytes to <to> bytes
    Reg zeroExtend(Reg intVal, int from, int to);
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

Reg wordLiteral(BackendFunction fun, Platform platform, size_t size)
{
    // TODO unsigned types
    switch (platform.nativeWordSize)
    {
        case 4:
            assert(size < int.max);
            return fun.intLiteral(cast(int) size);
        case 8:
            assert(size < long.max);
            return fun.longLiteral(size);
        default:
            assert(false, "unknown word size");
    }
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
