module backend.interpreter;

import stage1_libs;
import backend.backend;
import boilerplate;
import std.algorithm;
import std.array;
import std.format;
import std.range;

class IpBackend : Backend
{
    override IpBackendModule createModule() { return new IpBackendModule; }
}

class IpBackendType : BackendType
{
    abstract override string toString() const;

    abstract int size() const;
}

class IntType : IpBackendType
{
    override string toString() const { return "int"; }

    override int size() const { return 4; }
}

class CharType : IpBackendType
{
    override string toString() const { return "char"; }

    override int size() const { return 1; }
}

class VoidType : IpBackendType
{
    override string toString() const { return "void"; }

    override int size() const { return 0; }
}

class PointerType : IpBackendType
{
    override string toString() const { return "ptr"; }

    override int size() const { return size_t.sizeof; } // TODO machine

    mixin(GenerateThis);
}

class StructType : IpBackendType
{
    IpBackendType[] types;

    override string toString() const { return format!"{%(%s, %)}"(types); }

    // TODO alignment
    override int size() const { return this.types.map!"a.size".sum; }

    public size_t offsetOf(size_t field)
    in (field < this.types.length)
    {
        // TODO alignment
        return this.types[0 .. field].map!"a.size".sum;
    }

    mixin(GenerateThis);
}

string formatLiteral(const IpBackendType type, const void[] data)
{
    if (cast(IntType) type)
    {
        return format!"%s"((cast(int[]) data)[0]);
    }
    if (cast(VoidType) type)
    {
        return "void";
    }
    if (cast(PointerType) type) // hope it's char*
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
            IpBackendType type;
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
            IpBackendType type;
            void[] value;
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
            IpBackendType type;
        }
        static struct GetField
        {
            StructType structType;
            Reg base;
            int member;
        }
        static struct FieldOffset
        {
            StructType structType;
            Reg base;
            int member;
        }
        static struct Load
        {
            IpBackendType targetType;
            Reg target;
        }
        static struct Store
        {
            IpBackendType targetType;
            Reg target;
            Reg value;
        }
        static struct GetFuncPtr
        {
            string name;
        }
        static struct CallFuncPtr
        {
            IpBackendType type;
            Reg funcPtr;
            Reg[] args;
        }
        Call call;
        Return return_;
        Arg arg;
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

    int regSize(IpBackendFunction fun) const
    {
        with (Kind) final switch (this.kind)
        {
            case CallFuncPtr: return callFuncPtr.type.size;
            case Call: return call.type.size;
            case Arg: return fun.argTypes[arg.index].size;
            case Literal: return literal.type.size;
            case Load: return load.targetType.size;
            case GetField:
                return getField.structType.types[getField.member].size;
            // pointers
            // TODO machine based
            case Alloca:
            case FieldOffset:
            case GetFuncPtr:
                return size_t.sizeof;
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

    IpBackendType retType;

    IpBackendType[] argTypes;

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

        instr.literal.type = new IntType;
        instr.literal.value = cast(void[]) [value];

        return block.append(instr);
    }

    override Reg stringLiteral(string text)
    {
        import std.string : toStringz;

        auto instr = Instr(Instr.Kind.Literal);

        instr.literal.type = new PointerType;
        instr.literal.value = cast(void[]) [text.toStringz];

        return block.append(instr);
    }

    override int voidLiteral()
    {
        auto instr = Instr(Instr.Kind.Literal);

        instr.literal.type = new VoidType;
        instr.literal.value = null;

        return block.append(instr);
    }

    override int call(BackendType type, string name, Reg[] args)
    {
        assert(cast(IpBackendType) type !is null);
        auto instr = Instr(Instr.Kind.Call);

        instr.call.type = cast(IpBackendType) type;
        instr.call.name = name;
        instr.call.args = args.dup;
        return block.append(instr);
    }

    override int callFuncPtr(BackendType type, Reg funcPtr, Reg[] args)
    {
        assert(cast(IpBackendType) type !is null);
        auto instr = Instr(Instr.Kind.CallFuncPtr);

        instr.callFuncPtr.type = cast(IpBackendType) type;
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

    override int alloca(BackendType type)
    {
        assert(cast(IpBackendType) type !is null);

        auto instr = Instr(Instr.Kind.Alloca);

        instr.alloca.type = cast(IpBackendType) type;
        return block.append(instr);
    }

    override Reg field(BackendType structType, Reg structBase, int member)
    {
        assert(cast(StructType) structType !is null);

        auto instr = Instr(Instr.Kind.GetField);

        instr.getField.structType = cast(StructType) structType;
        instr.getField.base = structBase;
        instr.getField.member = member;

        return block.append(instr);
    }

    override Reg fieldOffset(BackendType structType, Reg structBase, int member)
    {
        assert(cast(StructType) structType !is null);

        auto instr = Instr(Instr.Kind.FieldOffset);

        instr.fieldOffset.structType = cast(StructType) structType;
        instr.fieldOffset.base = structBase;
        instr.fieldOffset.member = member;

        return block.append(instr);
    }

    override void store(BackendType targetType, Reg target, Reg value)
    {
        assert(cast(IpBackendType) targetType !is null);

        auto instr = Instr(Instr.Kind.Store);

        instr.store.targetType = cast(IpBackendType) targetType;
        instr.store.target = target;
        instr.store.value = value;

        block.append(instr);
    }

    override Reg load(BackendType targetType, Reg target)
    {
        assert(cast(IpBackendType) targetType !is null);

        auto instr = Instr(Instr.Kind.Load);

        instr.load.targetType = cast(IpBackendType) targetType;
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

void setInitValue(IpBackendType type, void* target)
{
    if (cast(IntType) type)
    {
        *cast(int*) target = 0;
        return;
    }
    if (auto strct = cast(StructType) type)
    {
        foreach (subtype; strct.types)
        {
            setInitValue(subtype, target);
            target += subtype.size;
        }
        return;
    }
    if (cast(PointerType) type)
    {
        *cast(void**) target = null;
        return;
    }
    assert(false, "what is init for " ~ type.toString);
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
        in (args.length == T.length)
        {
            T typedArgs;
            static foreach (i, U; T)
                typedArgs[i] = *cast(U*) args[i].ptr;
            *cast(R*) ret.ptr = dg(typedArgs);
        });
    }
    static foreach (key, op; [
        "add": "+", "sub": "-", "mul": "*", "div": "/",
        "eq": "==", "lt": "<", "gt": ">", "le": "<=", "ge": ">="
    ]) {
        defineCallback("cxruntime_int_" ~ key, delegate int(int a, int b) => mixin("a " ~ op ~ " b"));
    }
}

class IpBackendModule : BackendModule
{
    alias Callable = void delegate(void[] ret, void[][] args);
    Callable[string] callbacks;
    IpBackendFunction[string] functions;

    this()
    {
        defineIntrinsics(this);
    }

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
        size_t numRegs = fun.blocks.map!(block => block.instrs.length).sum;
        int regAreaSize = fun.blocks.map!(block => block.instrs.map!(instr => instr.regSize(fun)).sum).sum;

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
                regArrays[i++] = regCurrent[0 .. instr.regSize(fun)];
                regCurrent = regCurrent[instr.regSize(fun) .. $];
            }
            assert(regCurrent.length == 0);
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
                    final switch (instr.kind)
                    {
                        case Call:
                            assert(!lastInstr);
                            void[][] callArgs = instr.call.args.map!(reg => regArrays[reg]).array;

                            call(instr.call.name, regArrays[reg], callArgs);
                            break;
                        case CallFuncPtr:
                            assert(!lastInstr);
                            auto funcPtr = (cast(IpFuncPtr[]) regArrays[instr.callFuncPtr.funcPtr])[0];

                            void[][] callArgs = instr.callFuncPtr.args.map!(reg => regArrays[reg]).array;
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
                            assert(!lastInstr);
                            regArrays[reg][] = args[instr.arg.index];
                            break;
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
                            auto target = new void[instr.alloca.type.size];
                            setInitValue(instr.alloca.type, target.ptr);
                            (cast(void*[]) regArrays[reg])[0] = target.ptr;
                            break;
                        case FieldOffset:
                            assert(!lastInstr);
                            auto base = (cast(void*[]) regArrays[instr.fieldOffset.base])[0];
                            auto offset = instr.fieldOffset.structType.offsetOf(instr.fieldOffset.member);

                            (cast(void*[]) regArrays[reg])[0] = base + offset;
                            break;
                        case GetField:
                            assert(!lastInstr);
                            auto value = cast(ubyte[]) regArrays[instr.fieldOffset.base];
                            auto size = instr.getField.structType.types[instr.getField.member].size;
                            auto offset = instr.getField.structType.offsetOf(instr.getField.member);

                            (cast(ubyte[]) regArrays[reg])[] = value[offset .. offset + size];
                            break;
                        case Load:
                            assert(!lastInstr);
                            auto target = (cast(void*[]) regArrays[instr.load.target])[0];

                            regArrays[reg][] = target[0 .. regArrays[reg].length];
                            break;
                        case Store:
                            assert(!lastInstr);
                            auto target = (cast(void*[]) regArrays[instr.store.target])[0];

                            target[0 .. regArrays[instr.store.value].length] = regArrays[instr.store.value];
                            break;
                    }
                }
            }
        }
    }

    override IntType intType() { return new IntType; }

    override VoidType voidType() { return new VoidType; }

    override CharType charType() { return new CharType; }

    override IpBackendType structType(BackendType[] types)
    {
        assert(types.all!(a => cast(IpBackendType) a !is null));

        return new StructType(types.map!(a => cast(IpBackendType) a).array);
    }

    override IpBackendType pointerType(BackendType target)
    {
        assert(cast(IpBackendType) target);

        return new PointerType;
    }

    override IpBackendType funcPointerType(BackendType ret, BackendType[] args)
    {
        assert(cast(IpBackendType) ret);
        assert(args.all!(a => cast(IpBackendType) a));

        return new PointerType;
    }

    override IpBackendFunction define(string name, BackendType ret, BackendType[] args)
    in (name !in callbacks && name !in functions)
    {
        assert(cast(IpBackendType) ret);
        assert(args.all!(a => cast(IpBackendType) a));

        auto fun = new IpBackendFunction(name, cast(IpBackendType) ret, args.map!(a => cast(IpBackendType) a).array);

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
    auto mod = new IpBackendModule;
    auto square = mod.define("square", mod.intType, [mod.intType]);
    with (square) {
        auto arg0 = arg(0);
        auto reg = call(mod.intType, "cxruntime_int_mul", [arg0, arg0]);

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
    auto mod = new IpBackendModule;

    auto ack = mod.define("ack", mod.intType, [mod.intType, mod.intType]);

    with (ack)
    {
        auto m = arg(0);
        auto n = arg(1);
        auto zero = intLiteral(0);
        auto one = intLiteral(1);

        auto if1_test_reg = call(mod.intType, "cxruntime_int_eq", [m, zero]);
        auto if1_test_jumprecord = testBranch(if1_test_reg);

        if1_test_jumprecord.resolveThen(blockIndex);
        auto add = call(mod.intType, "cxruntime_int_add", [n, one]);
        ret(add);

        if1_test_jumprecord.resolveElse(blockIndex);
        auto if2_test_reg = call(mod.intType, "cxruntime_int_eq", [n, zero]);
        auto if2_test_jumprecord = testBranch(if2_test_reg);

        if2_test_jumprecord.resolveThen(blockIndex);
        auto sub = call(mod.intType, "cxruntime_int_sub", [m, one]);
        auto ackrec = call(mod.intType, "ack", [sub, one]);

        ret(ackrec);

        if2_test_jumprecord.resolveElse(blockIndex);
        auto n1 = call(mod.intType, "cxruntime_int_sub", [n, one]);
        auto ackrec1 = call(mod.intType, "ack", [m, n1]);
        auto m1 = call(mod.intType, "cxruntime_int_sub", [m, one]);
        auto ackrec2 = call(mod.intType, "ack", [m1, ackrec1]);
        ret(ackrec2);
    }

    int arg_m = 3, arg_n = 8;
    int ret;
    mod.call("ack", cast(void[]) (&ret)[0 .. 1], [cast(void[]) (&arg_m)[0 .. 1], cast(void[]) (&arg_n)[0 .. 1]]);
    ret.should.be(2045);
}

unittest
{
    /*
     * int square(int i) { int k = i; int l = k * k; return l; }
     */
    auto mod = new IpBackendModule;
    auto square = mod.define("square", mod.intType, [mod.intType]);
    auto stackframeType = mod.structType([mod.intType, mod.intType]);
    with (square) {
        auto stackframe = alloca(stackframeType);
        auto arg0 = arg(0);
        auto var = fieldOffset(stackframeType, stackframe, 0);
        store(mod.intType, var, arg0);
        auto varload = load(mod.intType, var);
        auto reg = call(mod.intType, "cxruntime_int_mul", [varload, varload]);
        auto retvar = fieldOffset(stackframeType, stackframe, 0);
        store(mod.intType, retvar, reg);

        auto retreg = load(mod.intType, retvar);
        ret(retreg);
    }

    int arg = 5;
    int ret;
    mod.call("square", cast(void[]) (&ret)[0 .. 1], [cast(void[]) (&arg)[0 .. 1]]);
    ret.should.be(25);
}

unittest
{
    auto mod = new IpBackendModule;
    auto fpType = mod.funcPointerType(mod.intType, []);
    auto callFp = mod.define("callFp", mod.intType, [fpType]);
    auto retFive = mod.define("retFive", mod.intType, []);
    auto test = mod.define("test", mod.intType, []);

    callFp.ret(callFp.callFuncPtr(mod.intType, callFp.arg(0), []));
    retFive.ret(retFive.intLiteral(5));
    test.ret(test.call(mod.intType, "callFp", [test.getFuncPtr("retFive")]));

    int ret;
    mod.call("test", cast(void[]) (&ret)[0 .. 1], null);
    ret.should.be(5);
}
