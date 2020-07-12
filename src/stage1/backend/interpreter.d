module backend.interpreter;

import stage1_libs;
import backend.backend;
import backend.platform;
import backend.types;
import boilerplate;
import std.algorithm;
import std.array;
import std.ascii;
import std.format;
import std.traits : EnumMembers;
import std.range;
import std.typecons : Tuple;

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
    if (cast(BackendLongType) type)
    {
        return format!"%s"((cast(long[]) data)[0]);
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
        ZeroExtend,
        SignExtend,
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
            static enum Ops = [
                "+", "-", "*", "/", "%",
                "&", "|", "^",
                "<", ">", "<=", ">=", "==",
            ];
            static enum Op {
                add, sub, mul, div, rem,
                and, or, xor,
                lt, gt, le, ge, eq,
            }
            static assert(Ops.length == EnumMembers!Op.length);
            Op op;
            int size; // 4, 8
            Reg left;
            Reg right;
        }
        static struct ZeroExtend
        {
            Reg value;
            int from, to;
        }
        static struct SignExtend
        {
            Reg value;
            int from, to;
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
            int size; // cache
        }
        static struct GetField
        {
            BackendStructType structType;
            Reg base;
            int member;
            int offset; // cache
        }
        static struct FieldOffset
        {
            BackendStructType structType;
            Reg base;
            int member;
            int offset; // cache
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
            BackendFunctionPointerType type;
            Reg funcPtr;
            Reg[] args;
        }
        Call call;
        Return return_;
        Arg arg;
        BinOp binop;
        ZeroExtend zeroExtend;
        SignExtend signExtend;
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
            case Literal: return format!"(%s) %s"(literal.type, formatLiteral(literal.type, literal.value));
            case BinOp: return format!"(%s) %%%s %s %%%s"(binop.size, binop.left, binop.op, binop.right);
            case ZeroExtend: return format!"%%%s %s->%s(0)"(zeroExtend.value, zeroExtend.from, zeroExtend.to);
            case SignExtend: return format!"%%%s %s->%s(s)"(signExtend.value, signExtend.from, signExtend.to);
            case Alloca: return format!"alloca %s"(alloca.type);
            case GetField: return format!"%%%s.%s (%s)"(
                getField.base, getField.member, getField.structType);
            case FieldOffset: return format!"&%%%s.%s (%s)"(
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
            case CallFuncPtr: return callFuncPtr.type.returnType.size(platform);
            case Call: return call.type.size(platform);
            case Arg: return fun.argTypes[arg.index].size(platform);
            case Literal: return literal.type.size(platform);
            case Load: return load.targetType.size(platform);
            case GetField:
                return getField.structType.members[getField.member].size(platform);
            case BinOp:
                with (Instr.BinOp.Op) final switch (binop.op) {
                    /// ops: + - * / % & | ^ < > <= >= ==
                    case eq: case gt: case ge: case lt: case le:
                        return intType.size(platform);
                    case add: case sub: case mul: case div: case rem: case and: case or: case xor:
                        return binop.size;
                }
            case ZeroExtend:
                return zeroExtend.to;
            case SignExtend:
                return signExtend.to;
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
        case ZeroExtend:
        case SignExtend:
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

    IpBackendModule module_;

    @(This.Init!null)
    BasicBlock[] blocks;

    @(This.Init!null)
    int[string] blockIds; // maps block labels to ids

    @(This.Init!null)
    void delegate(int)[][string] labelActions; // called once a block label/id mapping is established

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

    override int arg(int index)
    {
        auto instr = Instr(Instr.Kind.Arg);

        instr.arg.index = index;
        return block.append(instr);
    }

    override int intLiteral(long value)
    {
        auto instr = Instr(Instr.Kind.Literal);
        assert(value <= int.max, format!"!? %s"(value));

        instr.literal.type = new BackendIntType;
        instr.literal.value = cast(void[]) [cast(int) value];

        return block.append(instr);
    }

    override int longLiteral(long value)
    {
        auto instr = Instr(Instr.Kind.Literal);

        instr.literal.type = new BackendLongType;
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

    override Reg symbolList(string name)
    {
        auto instr = Instr(Instr.Kind.Literal);

        assert(name in module_.symbolLists, format!"symbol list '%s' not found in module"(name));

        instr.literal.type = new BackendPointerType(new BackendVoidType);
        instr.literal.value = cast(void[]) [module_.symbolLists[name].ptr];

        return block.append(instr);
    }

    override int call(BackendType type, string name, Reg[] args)
    {
        auto instr = Instr(Instr.Kind.Call);

        instr.call.type = type;
        instr.call.name = name;
        instr.call.args = args.dup;
        return block.append(instr);
    }

    override int callFuncPtr(BackendType type, Reg funcPtr, Reg[] args)
    {
        assert(cast(BackendFunctionPointerType) type !is null);
        auto instr = Instr(Instr.Kind.CallFuncPtr);

        instr.callFuncPtr.type = cast(BackendFunctionPointerType) type;
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

    override Reg binop(string op, int size, Reg left, Reg right)
    in (size == 4 || size == 8)
    {
        auto instr = Instr(Instr.Kind.BinOp);

        /// ops: + - * / % & | ^ < > <= >= ==
        instr.binop.op = {
            with (Instr.BinOp.Op) switch (op) {
                case "+": return add;
                case "-": return sub;
                case "*": return mul;
                case "/": return div;
                case "%": return rem;
                case "&": return and;
                case "|": return or;
                case "^": return xor;
                case "<": return lt;
                case ">": return gt;
                case "<=": return le;
                case ">=": return ge;
                case "==": return eq;
                default: assert(false, "unknown op " ~ op);
            }
        }();
        instr.binop.size = size;
        instr.binop.left = left;
        instr.binop.right = right;
        return block.append(instr);
    }

    override Reg zeroExtend(Reg value, int from, int to)
    {
        auto instr = Instr(Instr.Kind.ZeroExtend);

        instr.zeroExtend.value = value;
        instr.zeroExtend.from = from;
        instr.zeroExtend.to = to;
        return block.append(instr);
    }

    override Reg signExtend(Reg value, int from, int to)
    {
        auto instr = Instr(Instr.Kind.SignExtend);

        instr.signExtend.value = value;
        instr.signExtend.from = from;
        instr.signExtend.to = to;
        return block.append(instr);
    }

    override int alloca(BackendType type)
    {
        auto instr = Instr(Instr.Kind.Alloca);

        instr.alloca.type = type;
        instr.alloca.size = type.size(this.module_.platform);
        return block.append(instr);
    }

    override Reg field(BackendType type, Reg structBase, int member)
    {
        auto instr = Instr(Instr.Kind.GetField);
        auto structType = cast(BackendStructType) type;
        assert(structType !is null);

        instr.getField.structType = structType;
        instr.getField.base = structBase;
        instr.getField.member = member;
        instr.getField.offset = structType.offsetOf(this.module_.platform, member);

        return block.append(instr);
    }

    override Reg fieldOffset(BackendType type, Reg structBase, int member)
    {
        auto instr = Instr(Instr.Kind.FieldOffset);
        auto structType = cast(BackendStructType) type;
        assert(structType !is null);

        instr.fieldOffset.structType = structType;
        instr.fieldOffset.base = structBase;
        instr.fieldOffset.member = member;
        instr.fieldOffset.offset = structType.offsetOf(this.module_.platform, member);

        return block.append(instr);
    }

    override void store(BackendType targetType, Reg target, Reg value)
    {
        auto instr = Instr(Instr.Kind.Store);

        instr.store.targetType = targetType;
        instr.store.target = target;
        instr.store.value = value;

        block.append(instr);
    }

    override Reg load(BackendType targetType, Reg target)
    {
        auto instr = Instr(Instr.Kind.Load);

        instr.load.targetType = targetType;
        instr.load.target = target;

        return block.append(instr);
    }

    override void testBranch(Reg test, string thenLabel, string elseLabel)
    {
        auto instr = Instr(Instr.Kind.TestBranch);
        auto block = block;

        instr.testBranch.test = test;
        instr.testBranch.thenBlock = -1;
        instr.testBranch.elseBlock = -1;

        block.append(instr);
        assert(block.finished);

        resolveLabel(thenLabel, (int target) { block.instrs[$ - 1].testBranch.thenBlock = target; });
        resolveLabel(elseLabel, (int target) { block.instrs[$ - 1].testBranch.elseBlock = target; });
    }

    override void branch(string label)
    {
        auto instr = Instr(Instr.Kind.Branch);
        auto block = block;

        instr.branch.targetBlock = -1;

        block.append(instr);
        assert(block.finished);

        resolveLabel(label, (int target) { block.instrs[$ - 1].branch.targetBlock = target; });
    }

    override string getLabel()
    {
        block; // allocate new block

        auto blockId = cast(int) (this.blocks.length - 1);
        auto label = format!"Block%s"(blockId);

        this.blockIds[label] = blockId;
        return label;
    }

    override void setLabel(string label)
    {
        block; // allocate new block

        auto blockId = cast(int) (this.blocks.length - 1);

        assert(label in this.labelActions, format!"label %s not in actions"(label));
        foreach (action; this.labelActions[label])
            action(blockId);
        this.labelActions.remove(label);
        this.blockIds[label] = blockId;
    }

    void resolveLabel(string label, void delegate(int) action)
    {
        this.labelActions[label] ~= action;
        // backwards jump
        if (auto blockId = label in this.blockIds)
        {
            foreach (prevAction; this.labelActions[label])
                prevAction(*blockId);
            this.labelActions.remove(label);
        }
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

class IpFuncPtr
{
    IpBackendModule mod;

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
            {
                assert(
                    args[i].length == U.sizeof,
                    format!"arg %s has invalid size %s for %s"(i + 1, args[i].length, U.sizeof));
                typedArgs[i] = *cast(U*) args[i].ptr;
            }
            static if (is(typeof(dg(typedArgs)) == void))
            {
                dg(typedArgs);
            }
            else
            {
                *cast(typeof(dg(typedArgs))*) ret.ptr = dg(typedArgs);
            }
        });
    }
    defineCallback("_backendModule", delegate BackendModule() => mod);
    defineCallback("cxruntime_isAlpha", delegate int(char ch) => isAlpha(ch));
    defineCallback("cxruntime_isDigit", delegate int(char ch) => isDigit(ch));
    defineCallback("cxruntime_ptr_test", delegate int(void* p) => !!p);
    defineCallback("assert", (int test) { assert(test, "Assertion failed!"); });
    defineCallback("ptr_offset", delegate void*(void* ptr, size_t offset) { assert(offset >= 0); return ptr + offset; });
    defineCallback("cxruntime_file_exists", delegate int(string name) {
        import std.file : exists;

        return name.exists;
    });
    defineCallback("cxruntime_file_read", delegate string(string name) {
        import std.file : readText;

        return name.readText;
    });
    defineCallback("cxruntime_file_write", delegate void(string name, string data) {
        import std.file : write;

        name.write(data);
    });
    defineCallback("cxruntime_alloc", (size_t size) {
        // import std.stdio : writefln; writefln!"malloc %s"(size);
        assert(size >= 0 && size < 128*1024*1024);
        return (new void[size]).ptr;
    });
    defineCallback("memcpy", (void* target, void* source, size_t size) {
        import core.stdc.string : memcpy;

        memcpy(target, source, size);
    });
    defineCallback("print", (string text) {
        import core.stdc.stdio : printf;

        printf("%.*s\n", text.length, text.ptr);
    });
    defineCallback("strlen", (char* text) {
        import std.conv : to;

        return cast(int) text.to!string.length;
    });
    defineCallback("strncmp", (char* text, char* cmp, int limit) { return int(text[0 .. limit] == cmp[0 .. limit]); });
    defineCallback("cxruntime_atoi", (char[] text) {
        import std.conv : parse;

        return parse!int(text);
    });
    defineCallback("cxruntime_itoa", (int num) {
        import std.format : format;

        return format!"%s"(num);
    });
    defineCallback("cxruntime_ltoa", (long num) {
        import std.format : format;

        return format!"%s"(num);
    });
    // helper because we don't have pointer math
    defineCallback("cxruntime_linenr", delegate int(string haystack, string needle, int* linep, int* columnp) {
        if (needle.ptr < haystack.ptr && needle.ptr >= haystack.ptr + haystack.length)
            return false;
        foreach (i, line; haystack.splitter("\n").enumerate)
        {
            if (needle.ptr >= line.ptr && needle.ptr <= line.ptr + line.length)
            {
                *linep = cast(int) i;
                *columnp = cast(int) (needle.ptr - line.ptr);
                return true;
            }
        }
        assert(false);
    });

    defineCallback("_backend_createModule", delegate BackendModule(Backend backend, Platform platform)
        => backend.createModule(platform));
    defineCallback("_backend_longType", delegate BackendType() => new BackendLongType);
    defineCallback("_backend_intType", delegate BackendType() => new BackendIntType);
    defineCallback("_backend_charType", delegate BackendType() => new BackendCharType);
    defineCallback("_backend_voidType", delegate BackendType() => new BackendVoidType);
    defineCallback("_backend_pointerType", delegate BackendType(BackendType target)
        => new BackendPointerType(target));
    defineCallback("_backend_functionPointerType", delegate BackendType(BackendType ret, BackendType[] args)
        => new BackendFunctionPointerType(ret, args));
    defineCallback("_backend_structType", delegate BackendType(BackendType[] members)
        => new BackendStructType(members));

    defineCallback("_platform_size", delegate int(Platform platform, BackendType type)
        => type.size(platform));
    defineCallback("_platform_nativeWordSize", delegate int(Platform platform)
        => platform.nativeWordSize);

    defineCallback(
        "_backendModule_define",
        delegate BackendFunction(
            BackendModule mod, string name, BackendType ret, BackendType[] args)
        {
            return mod.define(name, ret, args);
        }
    );
    defineCallback("_backendModule_defineSymbolList",
        (BackendModule mod, string name, string[] symbols) {
            mod.defineSymbolList(name, symbols);
        }
    );
    defineCallback("_backendModule_backend",
        delegate Backend(BackendModule mod) { return mod.backend; });
    defineCallback("_backendModule_platform",
        delegate Platform(BackendModule mod) { return mod.platform; });
    defineCallback("_arraycmp", (void* left, void* right, size_t leftlen, size_t rightlen, size_t elemsize)
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
    // helper so I don't have to work out string[] conversion in cx
    defineCallback(
        "_backendModule_callMain",
        delegate void(BackendModule mod, string[] args)
        {
            // TODO hardcode interpreter backend in target environment
            (cast(IpBackendModule) mod).call("_main", null, [cast(void[]) [args]]);
        }
    );
    // used for macro hooking
    defineCallback(
        "_backendModule_callArity0",
        delegate void*(BackendModule mod, string name)
        {
            // TODO hardcode interpreter backend in target environment
            void* target;
            (cast(IpBackendModule) mod).call(name, cast(void[]) ((&target)[0 .. 1]), null);
            return target;
        }
    );
    defineCallback(
        "_backendFunction_arg",
        delegate int(BackendFunction fun, int index) => fun.arg(index));
    defineCallback(
        "_backendFunction_intLiteral",
        delegate int(BackendFunction fun, long value) => fun.intLiteral(value));
    defineCallback(
        "_backendFunction_longLiteral",
        delegate int(BackendFunction fun, long value) => fun.longLiteral(value));
    defineCallback(
        "_backendFunction_wordLiteral",
        delegate int(BackendFunction fun, Platform platform, long value) {
            if (platform.nativeWordSize == 4)
                return fun.intLiteral(value);
            else if (platform.nativeWordSize == 8)
                return fun.longLiteral(value);
            else assert(false);
        });
    defineCallback(
        "_backendFunction_stringLiteral",
        delegate int(BackendFunction fun, string text) => fun.stringLiteral(text));
    defineCallback(
        "_backendFunction_voidLiteral",
        delegate int(BackendFunction fun) => fun.voidLiteral);
    defineCallback(
        "_backendFunction_symbolList",
        delegate int(BackendFunction fun, string name) => fun.symbolList(name));
    defineCallback(
        "_backendFunction_call",
        delegate int(BackendFunction fun, BackendType ret, char[] name, int[] args)
            => fun.call(ret, name.idup, args));
    defineCallback(
        "_backendFunction_getFuncPtr",
        delegate int(BackendFunction fun, string name)
            => fun.getFuncPtr(name));
    defineCallback(
        "_backendFunction_callFuncPtr",
        delegate int(BackendFunction fun, BackendType type, Reg funcPtr, Reg[] args)
            => fun.callFuncPtr(type, funcPtr, args));
    defineCallback(
        "_backendFunction_binop",
        delegate int(BackendFunction fun, char[] op, int size, int left, int right)
            => fun.binop(op.idup, size, left, right));
    defineCallback(
        "_backendFunction_zeroExtend",
        delegate int(BackendFunction fun, int reg, int from, int to)
            => fun.zeroExtend(reg, from, to));
    defineCallback(
        "_backendFunction_signExtend",
        delegate int(BackendFunction fun, int reg, int from, int to)
            => fun.signExtend(reg, from, to));
    defineCallback(
        "_backendFunction_alloca",
        delegate int(BackendFunction fun, BackendType type)
            => fun.alloca(type));
    defineCallback(
        "_backendFunction_load",
        delegate int(BackendFunction fun, BackendType dataType, int target) => fun.load(dataType, target));
    defineCallback(
        "_backendFunction_field",
        delegate int(BackendFunction fun, BackendType structType, int structValue, int member)
            => fun.field(structType, structValue, member));
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
        delegate void(BackendFunction fun, string label) => fun.branch(label));
    defineCallback(
        "_backendFunction_testBranch",
        delegate void(BackendFunction fun, int reg, string thenLabel, string elseLabel)
            => fun.testBranch(reg, thenLabel, elseLabel));
    defineCallback(
        "_backendFunction_setLabel",
        delegate void(BackendFunction fun, string label) => fun.setLabel(label));
    defineCallback(
        "_backendFunction_getLabel",
        delegate string(BackendFunction fun) => fun.getLabel);
}

struct StackAllocator
{
    void[] stack;

    size_t used;

    void resize(size_t target) {
        while (stack.length < target) {
            if (!stack.length) stack = new void[1];
            else stack.length = stack.length * 2;
        }
        // import std.stdio : writefln; writefln!"stack resized to %s"(stack.length);
    }

    static struct Record
    {
        void[] data;
        size_t offset;
    }

    Record allocate(size_t size)
    {
        if (used + size > stack.length) resize(used + size);
        size_t offset = used;
        used += size;
        return Record(this.stack[offset .. used], offset);
    }

    void free(size_t offset) {
        this.used = offset;
    }
}

class IpBackendModule : BackendModule
{
    IpBackend backend_;

    Platform platform_;

    alias Callable = void delegate(void[] ret, void[][] args);

    Callable[string] callbacks;

    IpBackendFunction[string] functions;

    void[][string] symbolLists;

    StackAllocator allocator;

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

    public override void defineSymbolList(string name, string[] symbols)
    {
        void*[] pointers;
        foreach (symbol; symbols)
        {
            if (auto value = symbol in symbolLists) pointers ~= value.ptr;
            else
            {
                pointers ~= cast(void*) new IpFuncPtr(this, symbol);
            }
        }
        symbolLists[name] = cast(void[]) pointers;
    }

    Tuple!(
        size_t, "numRegs",
        int, "regAreaSize",
        int[], "instrSizes",
        int[], "instrOffsets",
    )[string] regsizeCache;

    void call(string name, void[] ret, void[][] args)
    in (name in this.functions || name in this.callbacks, format!"function '%s' not found"(name))
    {
        import core.stdc.stdlib : alloca;
        import std.stdio : writefln;

        scope(failure) writefln!"in %s:"(name);

        if (auto dg = name in this.callbacks)
        {
            return (*dg)(ret, args);
        }

        // import std.stdio; writefln!"-------\ncall %s"(name);
        // foreach (arg; args) writefln!"  %s"(*cast(int*) arg.ptr);

        auto fun = this.functions[name];
        assert(
            args.length == fun.argTypes.length,
            format!"%s expected %s arguments, not %s"(name, fun.argTypes.length, args.length));
        size_t numRegs;
        int regAreaSize;
        int[] instrSizes;
        int[] instrOffsets;
        if (name in regsizeCache) {
            numRegs = regsizeCache[name].numRegs;
            regAreaSize = regsizeCache[name].regAreaSize;
            instrSizes = regsizeCache[name].instrSizes;
            instrOffsets = regsizeCache[name].instrOffsets;
        } else {
            foreach (block; fun.blocks) numRegs += block.instrs.length;
            int i;
            foreach (block; fun.blocks) foreach (instr; block.instrs) {
                int size = instr.regSize(fun, this.platform);
                instrSizes ~= size;
                instrOffsets ~= i;
                i += size;
            }
            regAreaSize = instrSizes.sum;
            regsizeCache[name] = typeof(regsizeCache[name])(numRegs, regAreaSize, instrSizes, instrOffsets);
        }

        auto regDataAllocation = allocator.allocate(regAreaSize);

        void[] regData = regDataAllocation.data;
        scope(success) allocator.free(regDataAllocation.offset);

        auto regArrayAllocation = allocator.allocate(numRegs * (void[]).sizeof);

        void[][] regArrays = cast(void[][]) regArrayAllocation.data;
        scope(success) allocator.free(regArrayAllocation.offset);
        // TODO embed offset in the instrs?

        int block = 0;
        while (true)
        {
            assert(block >= 0 && block < fun.blocks.length);

            foreach (i, instr; fun.blocks[block].instrs)
            {
                const lastInstr = i == fun.blocks[block].instrs.length - 1;

                int reg = fun.blocks[block].regBase + cast(int) i;
                regArrays[reg] = regData[instrOffsets[reg] .. instrOffsets[reg] + instrSizes[reg]];

                // import std.stdio : writefln; writefln!"%%%s = %s"(reg, instr);

                with (Instr.Kind)
                {
                    outer: final switch (instr.kind)
                    {
                        case Call:
                            assert(!lastInstr);
                            int len = cast(int) instr.call.args.length;
                            void[][] callArgs = (
                                cast(void[]*) allocator.allocate(len * (void[]).sizeof).data
                            )[0 .. len];
                            foreach (k, argReg; instr.call.args) callArgs[k] = regArrays[argReg];

                            call(instr.call.name, regArrays[reg], callArgs);
                            break;
                        case CallFuncPtr:
                            assert(!lastInstr);
                            IpFuncPtr funcPtr = (cast(IpFuncPtr[]) regArrays[instr.callFuncPtr.funcPtr])[0];
                            int len = cast(int) instr.callFuncPtr.args.length;
                            void[][] callArgs = (
                                cast(void[]*) allocator.allocate(len * (void[]).sizeof).data
                            )[0 .. len];
                            foreach (k, argReg; instr.callFuncPtr.args)
                                callArgs[k] = regArrays[argReg];

                            funcPtr.mod.call(funcPtr.name, regArrays[reg], callArgs);
                            break;
                        case GetFuncPtr:
                            assert(!lastInstr);
                            regArrays[reg][] = [
                                new IpFuncPtr(this, instr.getFuncPtr.name)];
                            break;
                        case Return:
                            assert(lastInstr);
                            assert(ret.length == regArrays[instr.return_.reg].length,
                                format!"%s != %s"(ret.length, regArrays[instr.return_.reg].length));
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
                            assert(regArrays[instr.binop.left].length == instr.binop.size);
                            assert(regArrays[instr.binop.right].length == instr.binop.size);
                            if (instr.binop.size == 4)
                            {
                                int left = *cast(int*) regArrays[instr.binop.left].ptr;
                                int right = *cast(int*) regArrays[instr.binop.right].ptr;
                                assert(regArrays[reg].length == 4);
                                final switch (instr.binop.op)
                                {
                                    static foreach (op; [EnumMembers!(Instr.BinOp.Op)])
                                    {
                                        case op:
                                            *cast(int*) regArrays[reg].ptr
                                                = mixin("left " ~ Instr.BinOp.Ops[op] ~ " right");
                                            break outer;
                                    }
                                }
                            }
                            else if (instr.binop.size == 8)
                            {
                                long left = *cast(long*) regArrays[instr.binop.left].ptr;
                                long right = *cast(long*) regArrays[instr.binop.right].ptr;
                                with (Instr.BinOp.Op) final switch (instr.binop.op)
                                {
                                    static foreach (op; [add, sub, mul, div, rem, and, or, xor])
                                    {
                                        case op:
                                            assert(regArrays[reg].length == 8);
                                            *cast(long*) regArrays[reg].ptr
                                                = mixin("left " ~ Instr.BinOp.Ops[op] ~ " right");
                                            break outer;
                                    }
                                    static foreach (op; [lt, gt, le, ge, eq])
                                    {
                                        case op:
                                            assert(regArrays[reg].length == 4);
                                            *cast(int*) regArrays[reg].ptr
                                                = mixin("left " ~ Instr.BinOp.Ops[op] ~ " right");
                                            break outer;
                                    }
                                }
                            }
                            assert(false);
                        case ZeroExtend:
                            assert(regArrays[instr.zeroExtend.value].length == instr.zeroExtend.from);
                            assert(regArrays[reg].length == instr.zeroExtend.to);
                            if (instr.zeroExtend.from == 4 && instr.zeroExtend.to == 8) {
                                int value = *cast(int*) regArrays[instr.zeroExtend.value];
                                *cast(ulong*) regArrays[reg].ptr = cast(uint) value;
                                break;
                            }
                            assert(false);
                        case SignExtend:
                            assert(regArrays[instr.signExtend.value].length == instr.signExtend.from);
                            assert(regArrays[reg].length == instr.signExtend.to);
                            if (instr.signExtend.from == 4 && instr.signExtend.to == 8) {
                                int value = *cast(int*) regArrays[instr.signExtend.value];
                                *cast(long*) regArrays[reg].ptr = value;
                                break;
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
                            assert(regArrays[instr.testBranch.test].length == int.sizeof);

                            auto testValue = *cast(int*) regArrays[instr.testBranch.test].ptr;

                            if (testValue) {
                                block = instr.testBranch.thenBlock;
                            } else {
                                block = instr.testBranch.elseBlock;
                            }
                            break;
                        case Alloca:
                            assert(!lastInstr);

                            auto target = allocator.allocate(instr.alloca.size).data;
                            (cast(ubyte[]) target)[] = 0;
                            (cast(void*[]) regArrays[reg])[0] = target.ptr;
                            break;
                        case FieldOffset:
                            assert(!lastInstr);
                            assert(regArrays[instr.fieldOffset.base].length == (void*).sizeof);

                            auto base = *cast(void**) regArrays[instr.fieldOffset.base].ptr;

                            *cast(void**) regArrays[reg] = base + instr.fieldOffset.offset;
                            break;
                        case GetField:
                            assert(!lastInstr);
                            auto value = cast(void[]) regArrays[instr.fieldOffset.base];
                            auto size = instr.getField.structType.members[instr.getField.member].size(this.platform);
                            auto offset = instr.getField.offset;

                            (cast(void[]) regArrays[reg])[] = value[offset .. offset + size];
                            break;
                        case Load:
                            assert(!lastInstr);
                            auto target = (cast(void*[]) regArrays[instr.load.target])[0];
                            assert(regArrays[reg]);
                            assert(cast(size_t) target > 0x100);

                            regArrays[reg][] = target[0 .. regArrays[reg].length];
                            break;
                        case Store:
                            assert(!lastInstr);
                            auto target = (cast(void*[]) regArrays[instr.store.target])[0];
                            assert(regArrays[instr.store.value]);
                            assert(cast(size_t) target > 0x100);
                            assert(
                                instr.store.targetType.size(this.platform) == regArrays[instr.store.value].length,
                                format!"can't store %s bytes, got %s"(
                                    instr.store.targetType.size(this.platform), regArrays[instr.store.value].length));

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

        auto fun = new IpBackendFunction(
            name, cast(BackendType) ret, args.map!(a => cast(BackendType) a).array, this);

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
