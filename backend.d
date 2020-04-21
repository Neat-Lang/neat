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
    enum Kind
    {
        Int,
        Void,
    }
    Kind kind;
    mixin(GenerateThis);
}

struct IpValue
{
    enum Kind
    {
        Int,
    }
    Kind kind;
    union
    {
        int i;
    }
    int get(T : int)() { return i; }
    static IpValue make(T : int)(int i) { auto ret = IpValue(Kind.Int); ret.i = i; return ret; }
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
            Call call;
            Return return_;
            Arg arg;
            Literal literal;
            TestBranch testBranch;
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
                            if (testValue.get!int) {
                                block = instr.testBranch.thenBlock;
                            } else {
                                block = instr.testBranch.elseBlock;
                            }
                            break;
                    }
                }
            }
        }
    }

    override IpBackendType intType() { return new IpBackendType(IpBackendType.Kind.Int); }

    override IpBackendType voidType() { return new IpBackendType(IpBackendType.Kind.Void); }

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
        return IpValue.make!int(args[0].get!int * args[1].get!int);
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
        return IpValue.make!int(args[0].get!int + args[1].get!int);
    });
    mod.defineCallback("int_sub", delegate IpValue(IpValue[] args)
    in (args.length == 2)
    {
        return IpValue.make!int(args[0].get!int - args[1].get!int);
    });
    mod.defineCallback("int_eq", delegate IpValue(IpValue[] args)
    in (args.length == 2)
    {
        return IpValue.make!int(args[0].get!int == args[1].get!int);
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
