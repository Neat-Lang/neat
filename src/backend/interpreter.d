module backend.interpreter;

import backend_deps;
import backend.backend;
import backend.value;
import boilerplate;
import std.algorithm;
import std.array;
import std.format;

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
                Value value;
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

        instr.literal.value = Value.make!int(value);
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

Value getInitValue(IpBackendType type)
{
    if (cast(IntType) type)
    {
        return Value.make!int(0);
    }
    if (auto strct = cast(StructType) type)
    {
        return Value.makeStruct(strct.types.map!getInitValue.array);
    }
    assert(false, "what is init for " ~ type.toString);
}

class IpBackendModule : BackendModule
{
    alias Callable = Value delegate(Value[]);
    Callable[string] callbacks;
    IpBackendFunction[string] functions;

    void defineCallback(string name, Callable call)
    in (name !in callbacks && name !in functions)
    {
        callbacks[name] = call;
    }

    Value call(string name, Value[] args...)
    in (name in this.functions || name in this.callbacks, format!"%s not found"(name))
    {
        if (name in this.callbacks)
        {
            return this.callbacks[name](args);
        }
        auto fun = this.functions[name];
        auto regs = new Value[fun.regCount];
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
                            Value[] callArgs = instr.call.args.map!(reg => regs[reg]).array;
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
                            Value testValue = regs[instr.testBranch.test];
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

                            assert(base.kind == Value.Kind.Pointer);
                            regs[reg] = base.asPointer.offset(instr.fieldOffset.member);
                            break;
                        case Load:
                            // TODO validate type
                            auto target = regs[instr.load.target];

                            assert(target.kind == Value.Kind.Pointer);
                            regs[reg] = target.asPointer.load;
                            break;
                        case Store:
                            auto target = regs[instr.store.target];

                            assert(target.kind == Value.Kind.Pointer);
                            target.asPointer.store(regs[instr.store.value]);
                            regs[reg] = Value.make!void;
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
    mod.defineCallback("int_mul", delegate Value(Value[] args)
    in (args.length == 2)
    {
        return Value.make!int(args[0].as!int * args[1].as!int);
    });
    auto square = mod.define("square", mod.intType, [mod.intType, mod.intType]);
    with (square.startBlock) {
        auto arg0 = arg(0);
        auto reg = call("int_mul", [arg0, arg0]);

        ret(reg);
    }

    mod.call("square", Value.make!int(5)).should.equal(Value.make!int(25));
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
    mod.defineCallback("int_add", delegate Value(Value[] args)
    in (args.length == 2)
    {
        return Value.make!int(args[0].as!int + args[1].as!int);
    });
    mod.defineCallback("int_sub", delegate Value(Value[] args)
    in (args.length == 2)
    {
        return Value.make!int(args[0].as!int - args[1].as!int);
    });
    mod.defineCallback("int_eq", delegate Value(Value[] args)
    in (args.length == 2)
    {
        return Value.make!int(args[0].as!int == args[1].as!int);
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

    mod.call("ack", Value.make!int(3), Value.make!int(8)).should.equal(Value.make!int(2045));
}

unittest
{
    /*
     * int square(int i) { int k = i; int l = k * k; return l; }
     */
    auto mod = new IpBackendModule;
    mod.defineCallback("int_mul", delegate Value(Value[] args)
    in (args.length == 2)
    {
        return Value.make!int(args[0].as!int * args[1].as!int);
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

    mod.call("square", Value.make!int(5)).should.equal(Value.make!int(25));
}
