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
    // Symbols can be functions, globals, or other symbols. Symbol list contains a pointer to the symbol.
    // Defining the same symbol list twice is a no-op. Defining two symbol lists with the same name but
    // different values is undefined.
    // This is intended for global vtables.
    void defineSymbolList(string name, string[] symbols);
    Backend backend();
    Platform platform();
}

interface BackendFunction
{
    Reg arg(int index);
    Reg call(BackendType type, string name, Reg[] args);
    Reg intLiteral(int value);
    Reg longLiteral(long value);
    Reg stringLiteral(string text);
    Reg voidLiteral();
    // Reg contains pointer to symbol list
    Reg symbolList(string name);
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
    // must be first in block. Block can have multiple labels.
    void setLabel(string label);
    string getLabel();
    void branch(string label);
    void testBranch(Reg test, string thenLabel, string elseLabel);
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
    // must be called before first instruction in block
    void resolve(int index);
}

/// ditto
interface TestBranchRecord
{
    // must be called before first instruction in block
    void resolveThen(int index);
    void resolveElse(int index);
}
