module backend;

import backend_deps;
import std.algorithm;
import std.array;
import std.format;

interface BackendBlock
{
    alias Reg = int;

    int index();
    Reg arg(int index);
    Reg call(string name, Reg[] args);
    void ret(Reg);
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
            Call call;
            Return return_;
            Arg arg;
        }
    }

    @(This.Init!null)
    Instr[] instrs;

    override int index()
    {
        return this.index;
    }

    override int arg(int index)
    {
        auto instr = Instr(Instr.Kind.Arg);

        instr.arg.index = index;
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
                int reg = fun.blocks[block].regBase + cast(int) i;

                with (IpBackendBlock.Instr.Kind)
                {
                    final switch (instr.kind)
                    {
                        case Call:
                            IpValue[] callArgs = instr.call.args.map!(reg => regs[reg]).array;
                            regs[reg] = call(instr.call.name, callArgs);
                            break;
                        case Return:
                            return regs[instr.return_.reg];
                            break;
                        case Arg:
                            regs[reg] = args[instr.arg.index];
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
