module backend.interpreter;

import stage1_libs;
import backend.backend;
import backend.platform;
import backend.types;
import boilerplate;
import std.algorithm;
import std.array;
import std.format;
import std.range;

class IpBackend : Backend
{
    override IpBackendModule createModule(Platform platform) { return new IpBackendModule(this, platform); }

    mixin(GenerateThis);
}

string formatLiteral(const BackendType type, const void[] data)
{
    if (cast(BackendIntType) type)
    {
        return format!"%s"((cast(int[]) data)[0]);
    }
    if (cast(BackendVoidType) type)
    {
        return "void";
    }
    if (cast(BackendPointerType) type) // hope it's char*
    {
        import std.conv : to;

        return (*cast(char**) data).to!string;
    }
    assert(false, "TODO");
}

class BasicBlock
{
    int regBase;

    @(This.Init!false)
    bool finished;

    @(This.Init!null)
    Instr[] instrs;

    private int append(Instr instr)
    {
        assert(!this.finished);
        if (instr.kind.isBlockFinisher) this.finished = true;

        this.instrs ~= instr;
        return cast(int) (this.instrs.length - 1 + this.regBase);
    }

    override string toString() const
    {
        return instrs.enumerate.map!((pair) {
            if (pair.index == this.instrs.length - 1)
                return format!"    %s\n"(pair.value);
            return format!"    %%%s := %s\n"(this.regBase + pair.index, pair.value);
        }).join;
    }

    mixin(GenerateThis);
}

struct Instr
{
    enum Kind
    {
        Call,
        Arg,
        Literal,
        BinOp,
        Alloca,
        GetField,
        FieldOffset,
        Load,
        Store,
        // block finishers
        Return,
        Branch,
        TestBranch,
        GetFuncPtr,
        CallFuncPtr,
    }
    Kind kind;
    union
    {
        static struct Call
        {
            BackendType type;
            string name;
            Reg[] args;
        }
        static struct Return
        {
            Reg reg;
        }
        static struct Arg
        {
            int index;
        }
        static struct Literal
        {
            BackendType type;
            void[] value;
        }
        static struct BinOp
        {
            /// ops: + - * / % & | ^ < > <= >= ==
            string op;
            Reg left;
            Reg right;
        }
        static struct Branch
        {
            int targetBlock;
        }
        static struct TestBranch
        {
            Reg test;
            int thenBlock;
            int elseBlock;
        }
        static struct Alloca
        {
            BackendType type;
        }
        static struct GetField
        {
            BackendStructType structType;
            Reg base;
            int member;
        }
        static struct FieldOffset
        {
            BackendStructType structType;
            Reg base;
            int member;
        }
        static struct Load
        {
            BackendType targetType;
            Reg target;
        }
        static struct Store
        {
            BackendType targetType;
            Reg target;
            Reg value;
        }
        static struct GetFuncPtr
        {
            string name;
        }
        static struct CallFuncPtr
        {
            BackendType type;
            Reg funcPtr;
            Reg[] args;
        }
        Call call;
        Return return_;
        Arg arg;
        BinOp binop;
        Literal literal;
        Branch branch;
        TestBranch testBranch;
        Alloca alloca;
        GetField getField;
        FieldOffset fieldOffset;
        Load load;
        Store store;
        GetFuncPtr getFuncPtr;
        CallFuncPtr callFuncPtr;
    }

    string toString() const
    {
        with (Kind) final switch (this.kind)
        {
            case Call: return format!"%s %s(%(%%%s, %))"(call.type, call.name, call.args);
            case Arg: return format!"_%s"(arg.index);
            case Literal: return formatLiteral(literal.type, literal.value);
            case BinOp: return format!"%%%s %s %%%s"(binop.left, binop.op, binop.right);
            case Alloca: return format!"alloca %s"(alloca.type);
            case GetField: return format!"%%%s.%s (%s)"(
                getField.base, getField.member, getField.structType);
            case FieldOffset: return format!"%%%s.%s (%s)"(
                fieldOffset.base, fieldOffset.member, fieldOffset.structType);
            case Load: return format!"*%%%s"(load.target);
            case Store: return format!"*%%%s = %%%s"(store.target, store.value);
            case Return: return format!"ret %%%s"(return_.reg);
            case Branch: return format!"br blk%s"(branch.targetBlock);
            case TestBranch: return format!"tbr %%%s (then blk%s) (else blk%s)"(
                    testBranch.test,
                    testBranch.thenBlock,
                    testBranch.elseBlock,
                );
            case GetFuncPtr: return format!"funcptr %s"(getFuncPtr.name);
            case CallFuncPtr: return format!"%s %%%s(%(%%%s, %))"(
                callFuncPtr.type, callFuncPtr.funcPtr, callFuncPtr.args);
        }
    }

    int regSize(IpBackendFunction fun, Platform platform) const
    {
        static BackendType intType;
        if (!intType) intType = new BackendIntType;
        with (Kind) final switch (this.kind)
        {
            case CallFuncPtr: return platform.size(callFuncPtr.type);
            case Call: return platform.size(call.type);
            case Arg: return platform.size(fun.argTypes[arg.index]);
            case BinOp: return platform.size(intType);
            case Literal: return platform.size(literal.type);
            case Load: return platform.size(load.targetType);
            case GetField:
                return platform.size(getField.structType.members[getField.member]);
            // pointers
            case Alloca:
            case FieldOffset:
            case GetFuncPtr:
                return platform.nativeWordSize;
            // no-ops
            case Store:
            case Branch:
            case TestBranch:
            case Return:
                return 0;
        }
    }
}

private bool isBlockFinisher(Instr.Kind kind)
{
    with (Instr.Kind) final switch (kind)
    {
        case Return:
        case Branch:
        case TestBranch:
            return true;
        case Call:
        case Arg:
        case BinOp:
        case Literal:
        case Alloca:
        case GetField:
        case FieldOffset:
        case Load:
        case Store:
        case GetFuncPtr:
        case CallFuncPtr:
            return false;
    }
}

class IpBackendFunction : BackendFunction
{
    string name;

    BackendType retType;

    BackendType[] argTypes;

    @(This.Init!null)
    BasicBlock[] blocks;

    private BasicBlock block()
    {
        if (this.blocks.empty || this.blocks.back.finished)
        {
            int regBase = this.blocks.empty
                ? 0
                : (this.blocks.back.regBase + cast(int) this.blocks.back.instrs.length);

            this.blocks ~= new BasicBlock(regBase);
        }

        return this.blocks[$ - 1];
    }

    override int blockIndex()
    {
        block;
        return cast(int) (this.blocks.length - 1);
    }

    override int arg(int index)
    {
        auto instr = Instr(Instr.Kind.Arg);

        instr.arg.index = index;
        return block.append(instr);
    }

    override int intLiteral(int value)
    {
        auto instr = Instr(Instr.Kind.Literal);

        instr.literal.type = new BackendIntType;
        instr.literal.value = cast(void[]) [value];

        return block.append(instr);
    }

    override Reg stringLiteral(string text)
    {
        import std.string : toStringz;

        auto instr = Instr(Instr.Kind.Literal);

        instr.literal.type = new BackendPointerType(new BackendCharType);
        instr.literal.value = cast(void[]) [text.toStringz];

        return block.append(instr);
    }

    override int voidLiteral()
    {
        auto instr = Instr(Instr.Kind.Literal);

        instr.literal.type = new BackendVoidType;
        instr.literal.value = null;

        return block.append(instr);
    }

    override int call(BackendType type, string name, Reg[] args)
    {
        assert(cast(BackendType) type !is null);
        auto instr = Instr(Instr.Kind.Call);

        instr.call.type = cast(BackendType) type;
        instr.call.name = name;
        instr.call.args = args.dup;
        return block.append(instr);
    }

    override int callFuncPtr(BackendType type, Reg funcPtr, Reg[] args)
    {
        assert(cast(BackendType) type !is null);
        auto instr = Instr(Instr.Kind.CallFuncPtr);

        instr.callFuncPtr.type = cast(BackendType) type;
        instr.callFuncPtr.funcPtr = funcPtr;
        instr.callFuncPtr.args = args.dup;
        return block.append(instr);
    }

    override int getFuncPtr(string name)
    in (!name.empty)
    {
        auto instr = Instr(Instr.Kind.GetFuncPtr);

        instr.getFuncPtr.name = name;
        return block.append(instr);
    }

    override void ret(Reg reg)
    {
        auto instr = Instr(Instr.Kind.Return);

        instr.return_.reg = reg;
        block.append(instr);
    }

    override Reg binop(string op, Reg left, Reg right)
    {
        auto instr = Instr(Instr.Kind.BinOp);

        instr.binop.op = op;
        instr.binop.left = left;
        instr.binop.right = right;
        return block.append(instr);
    }

    override int alloca(BackendType type)
    {
        assert(cast(BackendType) type !is null);

        auto instr = Instr(Instr.Kind.Alloca);

        instr.alloca.type = cast(BackendType) type;
        return block.append(instr);
    }

    override Reg field(BackendType structType, Reg structBase, int member)
    {
        assert(cast(BackendStructType) structType !is null);

        auto instr = Instr(Instr.Kind.GetField);

        instr.getField.structType = cast(BackendStructType) structType;
        instr.getField.base = structBase;
        instr.getField.member = member;

        return block.append(instr);
    }

    override Reg fieldOffset(BackendType structType, Reg structBase, int member)
    {
        assert(cast(BackendStructType) structType !is null);

        auto instr = Instr(Instr.Kind.FieldOffset);

        instr.fieldOffset.structType = cast(BackendStructType) structType;
        instr.fieldOffset.base = structBase;
        instr.fieldOffset.member = member;

        return block.append(instr);
    }

    override void store(BackendType targetType, Reg target, Reg value)
    {
        assert(cast(BackendType) targetType !is null);

        auto instr = Instr(Instr.Kind.Store);

        instr.store.targetType = cast(BackendType) targetType;
        instr.store.target = target;
        instr.store.value = value;

        block.append(instr);
    }

    override Reg load(BackendType targetType, Reg target)
    {
        assert(cast(BackendType) targetType !is null);

        auto instr = Instr(Instr.Kind.Load);

        instr.load.targetType = cast(BackendType) targetType;
        instr.load.target = target;

        return block.append(instr);
    }

    override TestBranchRecord testBranch(Reg test)
    {
        auto instr = Instr(Instr.Kind.TestBranch);

        instr.testBranch.test = test;

        auto block = block;

        block.append(instr);

        assert(block.finished);

        return new class TestBranchRecord {
            override void resolveThen(int index)
            {
                block.instrs[$ - 1].testBranch.thenBlock = index;
            }
            override void resolveElse(int index)
            {
                block.instrs[$ - 1].testBranch.elseBlock = index;
            }
        };
    }

    override BranchRecord branch()
    {
        auto instr = Instr(Instr.Kind.Branch);
        auto block = block;

        block.append(instr);

        assert(block.finished);

        return new class BranchRecord {
            override void resolve(int index)
            {
                block.instrs[$ - 1].branch.targetBlock = index;
            }
        };
    }

    override string toString() const
    {
        return format!"%s %s(%(%s, %)):\n%s"(
            retType,
            name,
            argTypes,
            blocks.enumerate.map!(pair => format!"  blk%s:\n%s"(pair.index, pair.value)).join,
        );
    }

    mixin(GenerateThis);
}

void setInitValue(BackendType type, void* target, Platform platform)
{
    if (cast(BackendIntType) type)
    {
        *cast(int*) target = 0;
        return;
    }
    if (auto strct = cast(BackendStructType) type)
    {
        foreach (subtype; strct.members)
        {
            setInitValue(subtype, target, platform);
            // TODO alignment
            target += platform.size(subtype);
        }
        return;
    }
    if (cast(BackendPointerType) type || cast(BackendFunctionPointerType) type)
    {
        *cast(void**) target = null;
        return;
    }
    assert(false, format!"what is init for %s"(type));
}

struct ArrayAllocator(T)
{
    static T*[] pointers = null;

    static T[] allocate(size_t length)
    {
        if (length == 0) return null;

        int slot = findMsb(cast(int) length - 1);
        while (slot >= this.pointers.length) this.pointers ~= null;
        if (this.pointers[slot]) {
            auto ret = this.pointers[slot][0 .. length];
            this.pointers[slot] = *cast(T**) this.pointers[slot];
            return ret;
        }
        assert(length <= (1 << slot));
        auto allocSize = 1 << slot;

        // ensure we have space for the next-pointer
        while (T[1].sizeof * allocSize < (T*).sizeof) allocSize++;
        return (new T[allocSize])[0 .. length];
    }

    static void free(T[] array)
    {
        if (array.empty) return;

        int slot = findMsb(cast(int) array.length - 1);
        *cast(T**) array.ptr = this.pointers[slot];
        this.pointers[slot] = array.ptr;
    }
}

private int findMsb(int size)
{
    int bit_ = 0;
    while (size) {
        bit_ ++;
        size >>= 1;
    }
    return bit_;
}

unittest
{
    foreach (i, v; [0, 1, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 4, 4, 4, 4, 5])
        assert(findMsb(cast(int) i) == v);
}

class IpFuncPtr
{
    string name;

    mixin(GenerateAll);
}

private void defineIntrinsics(IpBackendModule mod)
{
    void defineCallback(R, T...)(string name, R delegate(T) dg)
    {
        mod.defineCallback(name, delegate void(void[] ret, void[][] args)
        in (args.length == T.length, "error calling " ~ name)
        {
            T typedArgs;
            static foreach (i, U; T)
                typedArgs[i] = args[i].as!U;
            static if (is(typeof(dg(typedArgs)) == void))
            {
                dg(typedArgs);
            }
            else
            {
                *cast(R*) ret.ptr = dg(typedArgs);
            }
        });
    }
    defineCallback("_backendModule", delegate BackendModule() => mod);
    defineCallback("cxruntime_int_negate", delegate int(int a) => !a);
    defineCallback("cxruntime_ptr_test", delegate int(void* p) => !!p);
    defineCallback("assert", (int test) { assert(test, "Assertion failed!"); });
    defineCallback("ptr_offset", delegate void*(void* ptr, int offset) { assert(offset >= 0); return ptr + offset; });
    defineCallback("malloc", (int size) {
        assert(size >= 0 && size < 1048576);
        return (new void[size]).ptr;
    });
    defineCallback("memcpy", (void* target, void* source, int size) {
        import core.stdc.string : memcpy;

        return memcpy(target, source, size);
    });
    defineCallback("print", (string text) {
        import std.stdio : writefln;

        writefln!"%s"(text);
    });
    defineCallback("strlen", (char* text) {
        import std.conv : to;

        return cast(int) text.to!string.length;
    });
    defineCallback("strncmp", (char* text, char* cmp, int limit) { return int(text[0 .. limit] == cmp[0 .. limit]); });
    defineCallback("atoi", (char[] text) {
        import std.conv : parse;

        return parse!int(text);
    });

    defineCallback("_backend_createModule", delegate BackendModule(Backend backend, Platform platform)
        => backend.createModule(platform));
    defineCallback("_backend_intType", delegate BackendType() => new BackendIntType);
    defineCallback("_backend_structType", delegate BackendType(BackendType[] members)
        => new BackendStructType(members.dup));
    defineCallback(
        "_backendModule_define",
        delegate BackendFunction(
            BackendModule mod, char[] name, BackendType ret, BackendType[] args)
        {
            return mod.define(name.dup, ret, args);
        }
    );
    defineCallback("_backendModule_backend",
        delegate Backend(BackendModule mod) { return mod.backend; });
    defineCallback("_backendModule_platform",
        delegate Platform(BackendModule mod) { return mod.platform; });
    defineCallback("_arraycmp", (void* left, void* right, int leftlen, int rightlen, int elemsize)
    {
        if (leftlen != rightlen) return 0;
        auto leftArray = (cast(ubyte*) left)[0 .. leftlen * elemsize];
        auto rightArray = (cast(ubyte*) right)[0 .. rightlen * elemsize];
        return leftArray == rightArray ? 1 : 0;
    });
    defineCallback("_backendModule_dump", delegate void(BackendModule mod)
    {
        import std.stdio : writefln;

        writefln!"(nested) module:\n%s"(mod);
    });
    defineCallback(
        "_backendModule_call",
        delegate void(BackendModule mod, void* ret, char[] name, void*[] args)
        {
            // TODO non-int args, ret
            // TODO hardcode interpreter backend in target environment
            (cast(IpBackendModule) mod).call(
                name.dup,
                ret[0 .. 4],
                args.map!(a => a[0 .. 4]).array,
            );
        }
    );
    defineCallback(
        "_backendFunction_arg",
        delegate int(BackendFunction fun, int index) => fun.arg(index));
    defineCallback(
        "_backendFunction_intLiteral",
        delegate int(BackendFunction fun, int index) => fun.intLiteral(index));
    defineCallback(
        "_backendFunction_voidLiteral",
        delegate int(BackendFunction fun) => fun.voidLiteral);
    defineCallback(
        "_backendFunction_call",
        delegate int(BackendFunction fun, BackendType ret, char[] name, int[] args)
            => fun.call(ret, name.idup, args));
    defineCallback(
        "_backendFunction_binop",
        delegate int(BackendFunction fun, char[] op, int left, int right)
            => fun.binop(op.idup, left, right));
    defineCallback(
        "_backendFunction_alloca",
        delegate int(BackendFunction fun, BackendType type)
            => fun.alloca(type));
    defineCallback(
        "_backendFunction_load",
        delegate int(BackendFunction fun, BackendType dataType, int target) => fun.load(dataType, target));
    defineCallback(
        "_backendFunction_fieldOffset",
        delegate int(BackendFunction fun, BackendType structType, int structBase, int member)
            => fun.fieldOffset(structType, structBase, member));
    defineCallback(
        "_backendFunction_store",
        delegate void(BackendFunction fun, BackendType dataType, int target, int value) => fun.store(dataType, target, value));
    defineCallback(
        "_backendFunction_ret",
        delegate void(BackendFunction fun, int value) => fun.ret(value));
    defineCallback(
        "_backendFunction_branch",
        delegate BranchRecord(BackendFunction fun) => fun.branch);
    defineCallback(
        "_backendFunction_testBranch",
        delegate TestBranchRecord(BackendFunction fun, int reg) => fun.testBranch(reg));
    defineCallback(
        "_backendFunction_blockIndex",
        delegate int(BackendFunction fun) => fun.blockIndex);

    defineCallback(
        "_branchRecord_resolve",
        delegate void(BranchRecord record, int block) => record.resolve(block));

    defineCallback(
        "_testBranchRecord_resolveThen",
        delegate void(TestBranchRecord record, int block) => record.resolveThen(block));
    defineCallback(
        "_testBranchRecord_resolveElse",
        delegate void(TestBranchRecord record, int block) => record.resolveElse(block));

}

private template as(T) {
    static if (is(T == U[], U))
    {
        T as(void[] arg) {
            struct ArrayHack { align(4) U* ptr; int length; }
            auto arrayVal = arg.as!ArrayHack;
            return arrayVal.ptr[0 .. arrayVal.length];
        }
    }
    else
    {
        ref T as(void[] arg) {
            assert(arg.length == T.sizeof, format!"arg has invalid size %s for %s"(arg.length, T.sizeof));
            return (cast(T[]) arg)[0];
        }
    }
}

class IpBackendModule : BackendModule
{
    IpBackend backend_;

    Platform platform_;

    alias Callable = void delegate(void[] ret, void[][] args);

    Callable[string] callbacks;

    IpBackendFunction[string] functions;

    this(IpBackend backend, Platform platform)
    {
        this.backend_ = backend;
        this.platform_ = platform;
        defineIntrinsics(this);
    }

    public override Backend backend() { return this.backend_; }

    public override Platform platform() { return this.platform_; }

    void defineCallback(string name, Callable call)
    in (name !in callbacks && name !in functions)
    {
        callbacks[name] = call;
    }

    void call(string name, void[] ret, void[][] args)
    in (name in this.functions || name in this.callbacks, format!"function '%s' not found"(name))
    {
        import core.stdc.stdlib : alloca;
        import std.stdio : writefln;

        scope(failure) writefln!"in %s:"(name);

        if (name in this.callbacks)
        {
            return this.callbacks[name](ret, args);
        }

        // import std.stdio; writefln!"-------\ncall %s"(name);
        // foreach (arg; args) writefln!"  %s"(*cast(int*) arg.ptr);

        auto fun = this.functions[name];
        assert(
            args.length == fun.argTypes.length,
            format!"%s expected %s arguments, not %s"(name, fun.argTypes.length, args.length));
        size_t numRegs;
        foreach (block; fun.blocks) numRegs += block.instrs.length;
        int regAreaSize;
        foreach (block; fun.blocks) foreach (instr; block.instrs) regAreaSize += instr.regSize(fun, this.platform);

        void[] regData = ArrayAllocator!void.allocate(regAreaSize);
        scope(success) ArrayAllocator!void.free(regData);

        void[][] regArrays = ArrayAllocator!(void[]).allocate(numRegs);
        scope(success) ArrayAllocator!(void[]).free(regArrays);
        // TODO embed offset in the instrs?
        {
            auto regCurrent = regData;
            int i;
            foreach (block; fun.blocks) foreach (instr; block.instrs)
            {
                regArrays[i++] = regCurrent[0 .. instr.regSize(fun, platform)];
                regCurrent = regCurrent[instr.regSize(fun, platform) .. $];
            }
            assert(regCurrent.length == 0);
            assert(i == numRegs);
        }

        int block = 0;
        while (true)
        {
            assert(block >= 0 && block < fun.blocks.length);

            foreach (i, instr; fun.blocks[block].instrs)
            {
                const lastInstr = i == fun.blocks[block].instrs.length - 1;

                int reg = fun.blocks[block].regBase + cast(int) i;

                // import std.stdio : writefln; writefln!"%%%s = %s"(reg, instr);

                with (Instr.Kind)
                {
                    outer: final switch (instr.kind)
                    {
                        case Call:
                            assert(!lastInstr);
                            int len = cast(int) instr.call.args.length;
                            void[][] callArgs = (cast(void[]*) alloca(len * (void[]).sizeof))[0 .. len];
                            foreach (k, argReg; instr.call.args) callArgs[k] = regArrays[argReg];

                            call(instr.call.name, regArrays[reg], callArgs);
                            break;
                        case CallFuncPtr:
                            assert(!lastInstr);
                            IpFuncPtr funcPtr = (cast(IpFuncPtr[]) regArrays[instr.callFuncPtr.funcPtr])[0];
                            int len = cast(int) instr.callFuncPtr.args.length;
                            void[][] callArgs = (cast(void[]*) alloca(len * (void[]).sizeof))[0 .. len];
                            foreach (k, argReg; instr.callFuncPtr.args)
                                callArgs[k] = regArrays[argReg];

                            call(funcPtr.name, regArrays[reg], callArgs);
                            break;
                        case GetFuncPtr:
                            assert(!lastInstr);
                            regArrays[reg][] = [
                                new IpFuncPtr(instr.getFuncPtr.name)];
                            break;
                        case Return:
                            assert(lastInstr);
                            ret[] = regArrays[instr.return_.reg];
                            return;
                        case Arg:
                            assert(regArrays[reg].ptr);
                            assert(!lastInstr);
                            assert(
                                regArrays[reg].length == args[instr.arg.index].length,
                                format!"load arg %s: expected sz %s, but got %s"(
                                    instr.arg.index, regArrays[reg].length, args[instr.arg.index].length));
                            regArrays[reg][] = args[instr.arg.index];
                            break;
                        case BinOp:
                            int left = (cast(int[]) regArrays[instr.binop.left])[0];
                            int right = (cast(int[]) regArrays[instr.binop.right])[0];
                            final switch (instr.binop.op)
                            {
                                static foreach (op;
                                    ["+", "-", "*", "/", "%", "&", "|", "^", "<", ">", "<=", ">=", "=="])
                                {
                                    case op:
                                        (cast(int[]) regArrays[reg])[0] = mixin("left " ~ op ~ " right");
                                        break outer;
                                }
                            }
                            assert(false);
                        case Literal:
                            assert(!lastInstr);
                            regArrays[reg][] = instr.literal.value;
                            break;
                        case Branch:
                            assert(lastInstr);
                            block = instr.branch.targetBlock;
                            break;
                        case TestBranch:
                            assert(lastInstr);
                            auto testValue = (cast(int[]) regArrays[instr.testBranch.test])[0];

                            if (testValue) {
                                block = instr.testBranch.thenBlock;
                            } else {
                                block = instr.testBranch.elseBlock;
                            }
                            break;
                        case Alloca:
                            assert(!lastInstr);
                            auto target = new void[this.platform.size(instr.alloca.type)];
                            setInitValue(instr.alloca.type, target.ptr, this.platform);
                            (cast(void*[]) regArrays[reg])[0] = target.ptr;
                            break;
                        case FieldOffset:
                            assert(!lastInstr);
                            auto base = (cast(void*[]) regArrays[instr.fieldOffset.base])[0];
                            auto offset = this.platform.offsetOf(instr.fieldOffset.structType, instr.fieldOffset.member);

                            (cast(void*[]) regArrays[reg])[0] = base + offset;
                            break;
                        case GetField:
                            assert(!lastInstr);
                            auto value = cast(void[]) regArrays[instr.fieldOffset.base];
                            auto size = this.platform.size(instr.getField.structType.members[instr.getField.member]);
                            auto offset = this.platform.offsetOf(instr.getField.structType, instr.getField.member);

                            (cast(void[]) regArrays[reg])[] = value[offset .. offset + size];
                            break;
                        case Load:
                            assert(!lastInstr);
                            auto target = (cast(void*[]) regArrays[instr.load.target])[0];
                            assert(regArrays[reg]);
                            assert(target);

                            regArrays[reg][] = target[0 .. regArrays[reg].length];
                            break;
                        case Store:
                            auto target = (cast(void*[]) regArrays[instr.store.target])[0];
                            assert(regArrays[instr.store.value]);
                            assert(target);

                            target[0 .. regArrays[instr.store.value].length] = regArrays[instr.store.value];
                            break;
                    }
                }
            }
        }
    }

    override IpBackendFunction define(string name, BackendType ret, BackendType[] args)
    in (name !in callbacks && name !in functions)
    {
        assert(cast(BackendType) ret);
        assert(args.all!(a => cast(BackendType) a));

        auto fun = new IpBackendFunction(name, cast(BackendType) ret, args.map!(a => cast(BackendType) a).array);

        this.functions[name] = fun;
        return fun;
    }

    override string toString() const
    {
        return
            callbacks.byKey.map!(a => format!"extern %s\n"(a)).join ~
            functions.byValue.map!(a => format!"%s\n"(a)).join;
    }
}

unittest
{
    auto mod = new IpBackendModule(new IpBackend, new DefaultPlatform);
    auto square = mod.define("square", new BackendIntType, [new BackendIntType]);
    with (square) {
        auto arg0 = arg(0);
        auto reg = binop("*", arg0, arg0);

        ret(reg);
    }

    int arg = 5;
    int ret;
    mod.call("square", cast(void[]) (&ret)[0 .. 1], [cast(void[]) (&arg)[0 .. 1]]);
    ret.should.be(25);
}

/+
    int ack(int m, int n) {
        if (m == 0) { return n + 1; }
        if (n == 0) { return ack(m - 1, 1); }
        return ack(m - 1, ack(m, n - 1));
    }
+/
unittest
{
    auto mod = new IpBackendModule(new IpBackend, new DefaultPlatform);

    auto ack = mod.define("ack", new BackendIntType, [new BackendIntType, new BackendIntType]);

    with (ack)
    {
        auto m = arg(0);
        auto n = arg(1);
        auto zero = intLiteral(0);
        auto one = intLiteral(1);

        auto if1_test_reg = binop("==", m, zero);
        auto if1_test_jumprecord = testBranch(if1_test_reg);

        if1_test_jumprecord.resolveThen(blockIndex);
        auto add = binop("+", n, one);
        ret(add);

        if1_test_jumprecord.resolveElse(blockIndex);
        auto if2_test_reg = binop("==", n, zero);
        auto if2_test_jumprecord = testBranch(if2_test_reg);

        if2_test_jumprecord.resolveThen(blockIndex);
        auto sub = binop("-", m, one);
        auto ackrec = call(new BackendIntType, "ack", [sub, one]);

        ret(ackrec);

        if2_test_jumprecord.resolveElse(blockIndex);
        auto n1 = binop("-", n, one);
        auto ackrec1 = call(new BackendIntType, "ack", [m, n1]);
        auto m1 = binop("-", m, one);
        auto ackrec2 = call(new BackendIntType, "ack", [m1, ackrec1]);
        ret(ackrec2);
    }

    int arg_m = 3, arg_n = 6;
    int ret;
    mod.call("ack", cast(void[]) (&ret)[0 .. 1], [cast(void[]) (&arg_m)[0 .. 1], cast(void[]) (&arg_n)[0 .. 1]]);
    ret.should.be(509);
}

unittest
{
    /*
     * int square(int i) { int k = i; int l = k * k; return l; }
     */
    auto mod = new IpBackendModule(new IpBackend, new DefaultPlatform);
    auto square = mod.define("square", new BackendIntType, [new BackendIntType]);
    auto stackframeType = new BackendStructType([new BackendIntType, new BackendIntType]);
    with (square) {
        auto stackframe = alloca(stackframeType);
        auto arg0 = arg(0);
        auto var = fieldOffset(stackframeType, stackframe, 0);
        store(new BackendIntType, var, arg0);
        auto varload = load(new BackendIntType, var);
        auto reg = binop("*", varload, varload);
        auto retvar = fieldOffset(stackframeType, stackframe, 0);
        store(new BackendIntType, retvar, reg);

        auto retreg = load(new BackendIntType, retvar);
        ret(retreg);
    }

    int arg = 5;
    int ret;
    mod.call("square", cast(void[]) (&ret)[0 .. 1], [cast(void[]) (&arg)[0 .. 1]]);
    ret.should.be(25);
}

unittest
{
    auto mod = new IpBackendModule(new IpBackend, new DefaultPlatform);
    auto fpType = new BackendFunctionPointerType(new BackendIntType, []);
    auto callFp = mod.define("callFp", new BackendIntType, [fpType]);
    auto retFive = mod.define("retFive", new BackendIntType, []);
    auto test = mod.define("test", new BackendIntType, []);

    callFp.ret(callFp.callFuncPtr(new BackendIntType, callFp.arg(0), []));
    retFive.ret(retFive.intLiteral(5));
    test.ret(test.call(new BackendIntType, "callFp", [test.getFuncPtr("retFive")]));

    int ret;
    mod.call("test", cast(void[]) (&ret)[0 .. 1], null);
    ret.should.be(5);
}
