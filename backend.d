module backend;

import backend_deps;
import std.algorithm;
import std.array;
import std.format;

// helper to allow delayed jump resolution
interface TestBranchRecord
{
    void resolveThen(int index);
    void resolveElse(int index);
}

interface BackendBlock
{
    alias Reg = int;

    int index();
    Reg arg(int index);
    Reg call(string name, Reg[] args);
    Reg literal(int value);
    Reg alloca(BackendType type);
    Reg fieldOffset(BackendType structType, Reg structBase, int member);
    void store(BackendType dataType, Reg target, Reg value);
    Reg load(BackendType dataType, Reg target);
    void ret(Reg);
    TestBranchRecord testBranch(Reg test);
}

interface BackendFunction
{
    BackendBlock startBlock();
}

interface BackendType
{
}

interface BackendModule
{
    BackendType intType();
    BackendType voidType();
    BackendType structType(BackendType[] types);
    BackendFunction define(string name, BackendType ret, BackendType[] args);
}

interface Backend
{
    BackendModule createModule();
}

class IpBackend : Backend
{
    override IpBackendModule createModule() { return new IpBackendModule; }
}

class IpBackendType : BackendType
{
}

class IntType : IpBackendType
{
}

class VoidType : IpBackendType
{
}

class StructType : IpBackendType
{
    IpBackendType[] types;
    mixin(GenerateThis);
}

struct IpValue
{
    enum Kind
    {
        Int,
        Void,
        Struct,
        Pointer,
    }
    Kind kind;
    union
    {
        int int_value;
        IpValue[] fields;
        PointerValue pointer_;
    }

    int as(T : int)()
    in (this.kind == Kind.Int)
    {
        return int_value;
    }

    PointerValue asPointer()
    in (this.kind == Kind.Pointer)
    {
        return this.pointer_;
    }

    ref IpValue accessField(int field)
    in (this.kind == Kind.Struct)
    {
        return this.fields[field];
    }

    static IpValue make(T : int)(int i)
    {
        auto ret = IpValue(Kind.Int);

        ret.int_value = i;
        return ret;
    }

    static IpValue make(T : void)()
    {
        return IpValue(Kind.Void);
    }

    static IpValue makeStruct(IpValue[] values)
    {
        auto ret = IpValue(Kind.Struct);

        ret.fields = values.dup;
        return ret;
    }

    static IpValue makePointer(PointerValue pointer)
    {
        auto ret = IpValue(Kind.Pointer);

        ret.pointer_ = pointer;
        return ret;
    }

    void checkSameType(IpValue other)
    {
        if (this.kind == Kind.Int && other.kind == Kind.Int)
        {
            return;
        }
        assert(false, "TODO");
    }

    string toString() const
    {
        final switch (this.kind)
        {
            case Kind.Int:
                return format!"%si"(this.int_value);
            case Kind.Void:
                return "void";
            case Kind.Pointer:
                return format!"&%s"(this.pointer_);
            case Kind.Struct:
                return format!"{%(%s, %)}"(this.fields);
        }
    }
}

/**
 * This type defines a region of addressable values.
 * It is used for the alloca region of stackframes, and the heap.
 */
class MemoryRegion
{
    IpValue[] values;

    IpValue allocate(IpValue value)
    {
        this.values ~= value;

        return IpValue.makePointer(PointerValue(this, [cast(int) this.values.length - 1]));
    }

    mixin(GenerateToString);
}

struct PointerValue
{
    private MemoryRegion base;

    // the value of the pointer is found by reading the value accessPath[0],
    // then following struct fields at each offset in turn.
    private int[] accessPath;

    invariant (accessPath.length >= 1);

    public IpValue load()
    {
        return refValue;
    }

    public void store(IpValue value)
    {
        refValue.checkSameType(value);
        refValue = value;
    }

    public IpValue offset(int member)
    in (refValue.kind == IpValue.Kind.Struct && member < refValue.fields.length,
        format("tried to take invalid offset %s of %s from %s", member, refValue, this))
    {
        return IpValue.makePointer(PointerValue(base, accessPath ~ member));
    }

    private ref IpValue refValue()
    {
        IpValue* current_value = &this.base.values[this.accessPath[0]];

        foreach (index; this.accessPath[1 .. $])
        {
            assert(current_value.kind == IpValue.Kind.Struct);

            current_value = &current_value.accessField(index);
        }
        return *current_value;
    }

    mixin(GenerateThis);
}

class IpBackendBlock : BackendBlock
{
    int index_;

    int regBase;

    static struct Instr
    {
        enum Kind
        {
            Call,
            Return,
            Arg,
            Literal,
            TestBranch,
            Alloca,
            FieldOffset,
            Load,
            Store,
        }
        Kind kind;
        union
        {
            static struct Call
            {
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
                IpValue value;
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
            Call call;
            Return return_;
            Arg arg;
            Literal literal;
            TestBranch testBranch;
            Alloca alloca;
            FieldOffset fieldOffset;
            Load load;
            Store store;
        }
    }

    @(This.Init!null)
    Instr[] instrs;

    override int index()
    {
        return this.index_;
    }

    override int arg(int index)
    {
        auto instr = Instr(Instr.Kind.Arg);

        instr.arg.index = index;
        return append(instr);
    }

    override int literal(int value)
    {
        auto instr = Instr(Instr.Kind.Literal);

        instr.literal.value = IpValue.make!int(value);
        return append(instr);
    }

    override int call(string name, Reg[] args)
    {
        auto instr = Instr(Instr.Kind.Call);

        instr.call.name = name;
        instr.call.args = args.dup;
        return append(instr);
    }

    override void ret(Reg reg)
    {
        auto instr = Instr(Instr.Kind.Return);

        instr.return_.reg = reg;
        append(instr);
    }

    override int alloca(BackendType type)
    in (cast(IpBackendType) type)
    {
        auto instr = Instr(Instr.Kind.Alloca);

        instr.alloca.type = cast(IpBackendType) type;
        return append(instr);
    }

    override Reg fieldOffset(BackendType structType, Reg structBase, int member)
    in (cast(StructType) structType)
    {
        auto instr = Instr(Instr.Kind.FieldOffset);

        instr.fieldOffset.structType = cast(StructType) structType;
        instr.fieldOffset.base = structBase;
        instr.fieldOffset.member = member;

        return append(instr);
    }

    override void store(BackendType targetType, Reg target, Reg value)
    in (cast(IpBackendType) targetType)
    {
        auto instr = Instr(Instr.Kind.Store);

        instr.store.targetType = cast(IpBackendType) targetType;
        instr.store.target = target;
        instr.store.value = value;

        append(instr);
    }

    override Reg load(BackendType targetType, Reg target)
    in (cast(IpBackendType) targetType)
    {
        auto instr = Instr(Instr.Kind.Load);

        instr.load.targetType = cast(IpBackendType) targetType;
        instr.load.target = target;

        return append(instr);
    }

    override TestBranchRecord testBranch(Reg test)
    {
        auto instr = Instr(Instr.Kind.TestBranch);

        instr.testBranch.test = test;

        auto offset = append(instr) - this.regBase;

        return new class TestBranchRecord {
            override void resolveThen(int index)
            {
                this.outer.instrs[offset].testBranch.thenBlock = index;
            }
            override void resolveElse(int index)
            {
                this.outer.instrs[offset].testBranch.elseBlock = index;
            }
        };
    }

    private int append(Instr instr)
    {
        this.instrs ~= instr;
        return cast(int) (this.instrs.length - 1 + this.regBase);
    }

    mixin(GenerateThis);
}

class IpBackendFunction : BackendFunction
{
    string name;

    IpBackendType ret;

    IpBackendType[] args;

    @(This.Init!null)
    IpBackendBlock[] blocks;

    override IpBackendBlock startBlock()
    {
        blocks ~= new IpBackendBlock(cast(int) blocks.length, regCount);
        return blocks[$-1];
    }

    int regCount()
    {
        return this.blocks.empty
            ? 0
            : this.blocks[$ - 1].regBase + cast(int) this.blocks[$ - 1].instrs.length;
    }

    mixin(GenerateThis);
}

IpValue getInitValue(IpBackendType type)
{
    if (cast(IntType) type)
    {
        return IpValue.make!int(0);
    }
    if (auto strct = cast(StructType) type)
    {
        return IpValue.makeStruct(strct.types.map!getInitValue.array);
    }
    assert(false, "what is init for " ~ type.toString);
}

class IpBackendModule : BackendModule
{
    alias Callable = IpValue delegate(IpValue[]);
    Callable[string] callbacks;
    IpBackendFunction[string] functions;

    void defineCallback(
        string name, IpValue delegate(IpValue[]) call)
    in (name !in callbacks && name !in functions)
    {
        callbacks[name] = call;
    }

    IpValue call(string name, IpValue[] args...)
    in (name in this.functions || name in this.callbacks, format!"%s not found"(name))
    {
        if (name in this.callbacks)
        {
            return this.callbacks[name](args);
        }
        auto fun = this.functions[name];
        auto regs = new IpValue[fun.regCount];
        auto allocaRegion = new MemoryRegion;

        int block = 0;
        while (true)
        {
            assert(block >= 0 && block < fun.blocks.length);

            foreach (i, instr; fun.blocks[block].instrs)
            {
                const lastInstr = i == fun.blocks[block].instrs.length - 1;

                int reg = fun.blocks[block].regBase + cast(int) i;

                with (IpBackendBlock.Instr.Kind)
                {
                    final switch (instr.kind)
                    {
                        case Call:
                            assert(!lastInstr);
                            IpValue[] callArgs = instr.call.args.map!(reg => regs[reg]).array;
                            regs[reg] = call(instr.call.name, callArgs);
                            break;
                        case Return:
                            assert(lastInstr);
                            return regs[instr.return_.reg];
                            break;
                        case Arg:
                            assert(!lastInstr);
                            regs[reg] = args[instr.arg.index];
                            break;
                        case Literal:
                            assert(!lastInstr);
                            regs[reg] = instr.literal.value;
                            break;
                        case TestBranch:
                            assert(lastInstr);
                            IpValue testValue = regs[instr.testBranch.test];
                            if (testValue.as!int) {
                                block = instr.testBranch.thenBlock;
                            } else {
                                block = instr.testBranch.elseBlock;
                            }
                            break;
                        case Alloca:
                            auto value = getInitValue(instr.alloca.type);

                            regs[reg] = allocaRegion.allocate(value);
                            break;
                        case FieldOffset:
                            // TODO validate type
                            auto base = regs[instr.fieldOffset.base];

                            assert(base.kind == IpValue.Kind.Pointer);
                            regs[reg] = base.asPointer.offset(instr.fieldOffset.member);
                            break;
                        case Load:
                            // TODO validate type
                            auto target = regs[instr.load.target];

                            assert(target.kind == IpValue.Kind.Pointer);
                            regs[reg] = target.asPointer.load;
                            break;
                        case Store:
                            auto target = regs[instr.store.target];

                            assert(target.kind == IpValue.Kind.Pointer);
                            target.asPointer.store(regs[instr.store.value]);
                            regs[reg] = IpValue.make!void;
                            break;
                    }
                }
            }
        }
    }

    override IntType intType() { return new IntType; }

    override IpBackendType voidType() { return new VoidType; }

    override IpBackendType structType(BackendType[] types)
    in (types.all!(a => cast(IpBackendType) a))
    {
        return new StructType(types.map!(a => cast(IpBackendType) a).array);
    }

    override IpBackendFunction define(string name, BackendType ret, BackendType[] args)
    in (name !in callbacks && name !in functions)
    in (cast(IpBackendType) ret)
    in (args.all!(a => cast(IpBackendType) a))
    {
        auto fun = new IpBackendFunction(name, cast(IpBackendType) ret, args.map!(a => cast(IpBackendType) a).array);

        this.functions[name] = fun;
        return fun;
    }
}

unittest
{
    auto mod = new IpBackendModule;
    mod.defineCallback("int_mul", delegate IpValue(IpValue[] args)
    in (args.length == 2)
    {
        return IpValue.make!int(args[0].as!int * args[1].as!int);
    });
    auto square = mod.define("square", mod.intType, [mod.intType, mod.intType]);
    with (square.startBlock) {
        auto arg0 = arg(0);
        auto reg = call("int_mul", [arg0, arg0]);

        ret(reg);
    }

    mod.call("square", IpValue.make!int(5)).should.equal(IpValue.make!int(25));
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
    mod.defineCallback("int_add", delegate IpValue(IpValue[] args)
    in (args.length == 2)
    {
        return IpValue.make!int(args[0].as!int + args[1].as!int);
    });
    mod.defineCallback("int_sub", delegate IpValue(IpValue[] args)
    in (args.length == 2)
    {
        return IpValue.make!int(args[0].as!int - args[1].as!int);
    });
    mod.defineCallback("int_eq", delegate IpValue(IpValue[] args)
    in (args.length == 2)
    {
        return IpValue.make!int(args[0].as!int == args[1].as!int);
    });

    auto ack = mod.define("ack", mod.intType, [mod.intType, mod.intType]);

    auto if1_test = ack.startBlock;
    auto m = if1_test.arg(0);
    auto n = if1_test.arg(1);
    auto zero = if1_test.literal(0);
    auto one = if1_test.literal(1);

    auto if1_test_reg = if1_test.call("int_eq", [m, zero]);
    auto if1_test_jumprecord = if1_test.testBranch(if1_test_reg);

    with (ack.startBlock) {
        if1_test_jumprecord.resolveThen(index);
        auto add = call("int_add", [n, one]);
        ret(add);
    }
    auto if2_test = ack.startBlock;
    if1_test_jumprecord.resolveElse(if2_test.index);
    auto if2_test_reg = if2_test.call("int_eq", [n, zero]);
    auto if2_test_jumprecord = if2_test.testBranch(if2_test_reg);

    with (ack.startBlock) {
        if2_test_jumprecord.resolveThen(index);
        auto sub = call("int_sub", [m, one]);
        auto ackrec = call("ack", [sub, one]);

        ret(ackrec);
    }

    with (ack.startBlock) {
        if2_test_jumprecord.resolveElse(index);
        auto n1 = call("int_sub", [n, one]);
        auto ackrec1 = call("ack", [m, n1]);
        auto m1 = call("int_sub", [m, one]);
        auto ackrec2 = call("ack", [m1, ackrec1]);
        ret(ackrec2);
    }

    mod.call("ack", IpValue.make!int(3), IpValue.make!int(8)).should.equal(IpValue.make!int(2045));
}

unittest
{
    /*
     * int square(int i) { int k = i; int l = k * k; return l; }
     */
    auto mod = new IpBackendModule;
    mod.defineCallback("int_mul", delegate IpValue(IpValue[] args)
    in (args.length == 2)
    {
        return IpValue.make!int(args[0].as!int * args[1].as!int);
    });
    auto square = mod.define("square", mod.intType, [mod.intType, mod.intType]);
    auto stackframeType = mod.structType([mod.intType, mod.intType]);
    with (square.startBlock) {
        auto stackframe = alloca(stackframeType);
        auto arg0 = arg(0);
        auto var = fieldOffset(stackframeType, stackframe, 0);
        store(mod.intType, var, arg0);
        auto varload = load(mod.intType, var);
        auto reg = call("int_mul", [varload, varload]);
        auto retvar = fieldOffset(stackframeType, stackframe, 0);
        store(mod.intType, retvar, reg);

        auto retreg = load(mod.intType, retvar);
        ret(retreg);
    }

    mod.call("square", IpValue.make!int(5)).should.equal(IpValue.make!int(25));
}
