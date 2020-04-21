module hello;

import boilerplate;
import std.algorithm;
import std.range;
import std.string;
import std.stdio;
import std.typecons;
import std.uni;

// something that can be referenced by a name
interface Symbol
{
}

class Type
{
    abstract void emit(Data* data);

    abstract size_t size() const;

    override string toString() const
    {
        assert(false);
    }
}

class Integer : Type
{
    override void emit(Data* data)
    {
        add_type_int(data);
    }

    override size_t size() const
    {
        return 4;
    }

    override string toString() const
    {
        return "int";
    }

    override bool opEquals(const Object obj)
    {
        return cast(Integer) obj !is null;
    }
}

class Void : Type
{
    override void emit(Data* data)
    {
        assert(false);
    }

    override size_t size() const
    {
        return 0;
    }

    override string toString() const
    {
        return "void";
    }

    override bool opEquals(const Object obj)
    {
        return cast(Void) obj !is null;
    }
}

class Struct : Type
{
    Type[] members;

    override void emit(Data* data)
    {
        add_type_struct(data, cast(int) this.members.length);
        this.members.each!(a => a.emit(data));
    }

    override size_t size() const
    {
        return members.map!(a => a.size).sum;
    }

    override string toString() const
    {
        return format!"{ %(%s, %) }"(this.members);
    }

    mixin(GenerateThis);
}

class Pointer : Type
{
    Type target;

    this(Type target)
    {
        this.target = target;
    }

    override size_t size() const
    {
        return 8;
    }

    override void emit(Data* data)
    {
        assert(false);
        // add_type_pointer(data);
        target.emit(data);
    }

    override string toString() const
    {
        return format!"%s*"(this.target);
    }
}

extern (C)
{
    struct Data
    {
        void* ptr;
        size_t length;
    }

    struct BytecodeBuilder
    {
        Data* data;
        size_t symbol_offsets_len;
        size_t* symbol_offsets_ptr;
    }

    struct DefineSectionState
    {
        Data* main_data;
        // ...
    }

    Data* alloc_data();
    BytecodeBuilder* alloc_bc_builder();
    size_t begin_declare_section(BytecodeBuilder* data);
    DefineSectionState* begin_define_section(BytecodeBuilder*, size_t index);
    void end_define_section(BytecodeBuilder* data, DefineSectionState* state);
    void declare_symbol(BytecodeBuilder* data, int args);
    void add_string(Data* data, const char* text);
    void add_type_int(Data* data);
    void add_type_struct(Data* data, int members);
    void end_declare_section(Data* data, size_t offset);

    void add_ret_instr(DefineSectionState* state, int reg);
    int add_tbr_instr(DefineSectionState* state, int reg);
    int add_literal_instr(DefineSectionState* state, int value);
    int add_arg_instr(DefineSectionState* state, int index);
    void tbr_resolve_then(DefineSectionState* state, int tbr_offset, int block);
    void tbr_resolve_else(DefineSectionState* state, int tbr_offset, int block);
    int add_br_instr(DefineSectionState* state);
    void br_resolve(DefineSectionState* state, int br_offset, int block);
    int start_call_instr(DefineSectionState* state, int offset, int args);
    void add_store_instr(DefineSectionState* state, int value_reg, int pointer_reg);
    size_t start_offset_instr(DefineSectionState* state, int reg, size_t index);
    int end_offset_instr(DefineSectionState* state, size_t offset);
    int emit_alloc_instr(DefineSectionState* state, size_t size);
    size_t start_load_instr(DefineSectionState* state, int pointer_reg);
    int end_load_instr(DefineSectionState* state, size_t offset);
    void add_call_reg_arg(DefineSectionState* state, int reg);
    int start_block(DefineSectionState* state);
}

class Generator
{
    BytecodeBuilder* builder;
    DefineSectionState* defineSectionState;

    invariant (builder !is null);

    int numDeclarations;

    Nullable!int frameReg_;

    void frameReg(int i)
    {
        this.frameReg_ = i;
    }

    void resetFrame()
    {
        this.frameReg_.nullify;
    }

    int frameReg()
    {
        return this.frameReg_.get;
    }

    this(BytecodeBuilder* builder, DefineSectionState* defineSectionState = null)
    {
        this.builder = builder;
        this.defineSectionState = defineSectionState;
    }

    template opDispatch(string name)
    {
        auto opDispatch(T...)(T args)
        {
            static string member()
            {
                switch (name)
                {
                    case "declare_symbol":
                        case "begin_declare_section":
                        return "this.builder";
                    case "end_declare_section":
                        case "add_string":
                        case "add_type_int":
                        assert(false, "specify data explicitly: may appear in either");
                    default:
                        return "this.defineSectionState";
                }
            }

            return mixin(name ~ "(" ~ member() ~ ", args)");
        }
    }
}

/*class BytecodeType
{
    enum Kind
    {
        Int,
        Void,
    }
    Kind kind;
    mixin(GenerateThis);
}

class BytecodeBackend : Backend
{
    Generator generator;

    int[string] declarations;

    override void declare(string name, BackendType ret, BackendType[] args)
    in (cast(BytecodeType) ret)
    in (args.all!(a => cast(BytecodeType) a))
    {
        declarations[name] = cast(int) generator.builder.symbol_offsets_len;
        size_t section = gen.begin_declare_section;
        gen.declare_symbol(args.length);
        add_string(gen.builder.data, toStringz(name));
        // add_type_
        // Are we really doing this? Just write an interpreter.
    }

    mixin(GenerateThis);
}*/

string genIntStub(string op)(Backend backend)
{
    auto int_ = backend.getIntType();
    auto name = "int_" ~ op;

    backend.declare(name, int_, [int_, int_]);
    return name;
}

int gen_int_stub(string op)(Generator gen)
{
    int offset = cast(int) gen.builder.symbol_offsets_len;
    size_t section = gen.begin_declare_section;
    gen.declare_symbol(2);
    add_string(gen.builder.data, toStringz("int_" ~ op));
    add_type_int(gen.builder.data); // ret
    add_type_int(gen.builder.data);
    add_type_int(gen.builder.data);
    end_declare_section(gen.builder.data, section);
    return offset;
}

class Parser
{
    string[] stack;

    invariant (!this.stack.empty);

    size_t level;

    invariant (this.level <= this.stack.length);

    @property ref string text()
    {
        return this.stack[this.level];
    }

    void begin()
    {
        if (this.level == this.stack.length - 1)
        {
            this.stack ~= this.text;
        }
        else
        {
            this.stack[this.level + 1] = this.text;
        }
        this.level++;
    }

    void commit()
    in (this.level > 0)
    {
        this.stack[this.level - 1] = text;
        this.level--;
    }

    void revert()
    in (this.level > 0)
    {
        this.level--;
    }

    this(string text)
    {
        this.stack ~= text;
    }

    bool accept(string match)
    {
        begin;

        strip;
        if (this.text.startsWith(match))
        {
            this.text = this.text.drop(match.length);
            commit;
            return true;
        }
        revert;
        return false;
    }

    void expect(string match)
    {
        if (!accept(match))
        {
            fail(format!"'%s' expected."(match));
        }
    }

    void fail(string msg)
    {
        assert(false, format!"at %s: %s"(this.text, msg));
    }

    void strip()
    {
        this.text = this.text.strip;
    }
}

bool parseNumber(ref Parser parser, out int i)
{
    import std.conv : to;

    with (parser)
    {
        begin;
        strip;
        if (text.empty || !text.front.isNumber)
        {
            revert;
            return false;
        }
        string number;
        while (!text.empty && text.front.isNumber)
        {
            number ~= text.front;
            text.popFront;
        }
        commit;
        i = number.to!int;
        return true;
    }
}

string parseIdentifier(ref Parser parser)
{
    with (parser)
    {
        begin;
        strip;
        if (text.empty || !text.front.isAlpha)
        {
            revert;
            return null;
        }
        string identifier;
        while (!text.empty && text.front.isAlphaNum)
        {
            identifier ~= text.front;
            text.popFront;
        }
        commit;
        return identifier;
    }
}

Type parseType(ref Parser parser)
{
    with (parser)
    {
        begin;

        if (parser.parseIdentifier == "int")
        {
            commit;
            return new Integer;
        }

        return null;
    }
}

struct Argument
{
    Type type;
    string name;
}

class Function : Symbol
{
    string name;

    Type ret;

    Argument[] args;

    ASTStatement statement;

    @(This.Init!(-1))
    int decl_offset;

    mixin(GenerateThis);
    mixin(GenerateToString);
}

void add_type(Data* data, Type type)
{
    if (cast(Integer) type)
    {
        add_type_int(data);
        return;
    }
    assert(false);
}

int declare(Generator output, Function fun)
{
    if (fun.decl_offset != -1)
        return fun.decl_offset;
    int offset = cast(int) output.builder.symbol_offsets_len;
    size_t section = output.begin_declare_section;
    output.declare_symbol(cast(int) fun.args.length);
    add_string(output.builder.data, fun.name.toStringz);
    add_type(output.builder.data, fun.ret);
    foreach (arg; fun.args)
    {
        add_type(output.builder.data, arg.type);
    }
    end_declare_section(output.builder.data, section);
    fun.decl_offset = offset;
    return fun.decl_offset;
}

interface ASTStatement
{
    Statement compile(Namespace namespace);
}

interface Statement
{
    void emit(Generator output);
}

interface ASTExpression : Symbol
{
    Expression compile(Namespace namespace);
}

interface Expression : Symbol
{
    Type type();
    int emit(Generator output);
}

interface Reference : Expression
{
    int emitLocation(Generator output);
}

Function parseFunction(ref Parser parser)
{
    with (parser)
    {
        begin;
        auto ret = parser.parseType;
        auto name = parser.parseIdentifier;
        expect("(");
        Argument[] args;
        while (!accept(")"))
        {
            if (!args.empty)
            {
                if (!accept(","))
                {
                    fail("',' or ')' expected");
                }
            }
            auto argtype = parser.parseType;
            auto argname = parser.parseIdentifier;
            args ~= Argument(argtype, argname);
        }
        auto stmt = parser.parseStatement;
        commit;
        return new Function(name, ret, args, stmt);
    }
}

class ASTScopeStatement : ASTStatement
{
    @AllNonNull
    ASTStatement[] statements;

    override Statement compile(Namespace namespace)
    {
        auto subscope = new VarDeclScope(namespace, No.frameBase);

        return new SequenceStatement(
                statements.map!(a => a.compile(subscope)).array
        );
    }

    mixin(GenerateAll);
}

class SequenceStatement : Statement
{
    @AllNonNull
    Statement[] statements;

    override void emit(Generator output)
    {
        foreach (statement; statements)
        {
            statement.emit(output);
        }
    }

    mixin(GenerateThis);
    mixin(GenerateToString);
}

ASTScopeStatement parseScope(ref Parser parser)
{
    with (parser)
    {
        begin;
        if (!accept("{"))
        {
            revert;
            return null;
        }
        ASTStatement[] statements;
        while (!accept("}"))
        {
            auto stmt = parser.parseStatement;
            statements ~= stmt;
        }
        commit;
        return new ASTScopeStatement(statements);
    }
}

class ASTReturnStatement : ASTStatement
{
    ASTExpression value;

    override ReturnStatement compile(Namespace namespace)
    {
        return new ReturnStatement(value.compile(namespace));
    }

    mixin(GenerateAll);
}

class ReturnStatement : Statement
{
    Expression value;

    override void emit(Generator output)
    {
        int reg = this.value.emit(output);
        output.add_ret_instr(reg);
        output.start_block;
    }

    mixin(GenerateAll);
}

ASTReturnStatement parseReturn(ref Parser parser)
{
    with (parser)
    {
        begin;
        if (parser.parseIdentifier != "return")
        {
            revert;
            return null;
        }
        auto expr = parser.parseExpression;
        expect(";");
        commit;
        return new ASTReturnStatement(expr);
    }
}

class ASTIfStatement : ASTStatement
{
    ASTExpression test;
    ASTStatement then;

    override IfStatement compile(Namespace namespace)
    {
        auto ifscope = new VarDeclScope(namespace, No.frameBase);
        auto test = this.test.compile(ifscope);
        auto then = this.then.compile(ifscope);

        return new IfStatement(test, then);
    }

    mixin(GenerateAll);
}

class IfStatement : Statement
{
    Expression test;
    Statement then;

    override void emit(Generator output)
    {
        int reg = test.emit(output);
        int tbr_offset = output.add_tbr_instr(reg);
        int thenblk = output.start_block;
        output.tbr_resolve_then(tbr_offset, thenblk);
        then.emit(output);
        int after_then = output.add_br_instr;
        // TODO else blk
        int afterblk = output.start_block;
        output.tbr_resolve_else(tbr_offset, afterblk);
        output.br_resolve(after_then, afterblk);
    }

    mixin(GenerateThis);
    mixin(GenerateToString);
}

ASTIfStatement parseIf(ref Parser parser)
{
    with (parser)
    {
        begin;
        if (parser.parseIdentifier != "if")
        {
            revert;
            return null;
        }
        parser.expect("(");
        auto expr = parser.parseExpression;
        parser.expect(")");
        auto thenStmt = parser.parseStatement;
        commit;
        return new ASTIfStatement(expr, thenStmt);
    }
}

class ASTAssignStatement : ASTStatement
{
    ASTExpression target;

    ASTExpression value;

    override AssignStatement compile(Namespace namespace)
    {
        auto target = this.target.compile(namespace);
        auto value = this.value.compile(namespace);
        auto targetref = cast(Reference) target;
        assert(targetref, "target of assignment must be a reference");
        return new AssignStatement(targetref, value);
    }

    mixin(GenerateAll);
}

class AssignStatement : Statement
{
    Reference target;
    Expression value;

    override void emit(Generator output)
    {
        auto targetType = this.target.type(), valueType = this.value.type();
        assert(targetType == valueType,
                format!"%s - %s => %s - %s"(this.target, this.value, targetType, valueType));

        int target_reg = this.target.emitLocation(output);
        int value_reg = this.value.emit(output);

        output.add_store_instr(value_reg, target_reg);
        valueType.emit(output.defineSectionState.main_data);
    }

    mixin(GenerateAll);
}

ASTAssignStatement parseAssignment(ref Parser parser)
{
    with (parser)
    {
        begin;
        auto lhs = parser.parseIdentifier;
        if (!lhs || !accept("="))
        {
            revert;
            return null;
        }
        auto expr = parser.parseExpression;
        expect(";");
        commit;
        return new ASTAssignStatement(new Variable(lhs), expr);
    }
}

class ASTVarDeclStatement : ASTStatement
{
    string name;

    Type type;

    ASTExpression initial;

    override Statement compile(Namespace namespace)
    {
        auto initial = this.initial.compile(namespace);

        return namespace.find!VarDeclScope.declare(this.name, initial);
    }

    mixin(GenerateAll);
}

ASTVarDeclStatement parseVarDecl(ref Parser parser)
{
    with (parser)
    {
        begin;
        auto type = parser.parseType;
        if (!type)
        {
            revert;
            return null;
        }
        auto name = parser.parseIdentifier;
        if (!name || !accept("="))
        {
            revert;
            return null;
        }
        auto initial = parser.parseExpression;
        expect(";");
        commit;
        return new ASTVarDeclStatement(name, type, initial);
    }
}

class ASTExprStatement : ASTStatement
{
    ASTExpression value;

    override Statement compile(Namespace namespace)
    {
        return new ExprStatement(this.value.compile(namespace));
    }

    mixin(GenerateAll);
}

class ExprStatement : Statement
{
    Expression value;

    override void emit(Generator output)
    {
        value.emit(output); // discard reg
    }

    mixin(GenerateAll);
}

ASTExprStatement parseExprStatement(ref Parser parser)
{
    with (parser)
    {
        begin;
        auto value = parser.parseExpression;
        if (!value)
        {
            revert;
            return null;
        }
        expect(";");
        commit;
        return new ASTExprStatement(value);
    }
}

ASTStatement parseStatement(ref Parser parser)
{
    if (auto stmt = parser.parseReturn)
        return stmt;
    if (auto stmt = parser.parseIf)
        return stmt;
    if (auto stmt = parser.parseScope)
        return stmt;
    if (auto stmt = parser.parseAssignment)
        return stmt;
    if (auto stmt = parser.parseVarDecl)
        return stmt;
    if (auto stmt = parser.parseExprStatement)
        return stmt;
    parser.fail("statement expected");
    assert(false);
}

ASTExpression parseExpression(ref Parser parser)
{
    if (auto expr = parser.parseCall)
    {
        return expr;
    }

    return parser.parseArithmetic;
}

enum ArithmeticOpType
{
    add,
    sub,
    eq,
}

class ASTArithmeticOp : ASTExpression
{
    ArithmeticOpType op;
    ASTExpression left;
    ASTExpression right;

    override ArithmeticOp compile(Namespace namespace)
    {
        return new ArithmeticOp(op, left.compile(namespace), right.compile(namespace));
    }

    mixin(GenerateAll);
}

class ArithmeticOp : Expression
{
    ArithmeticOpType op;
    Expression left;
    Expression right;

    override Type type()
    {
        return new Integer;
    }

    override int emit(Generator output)
    {
        int leftreg = this.left.emit(output);
        int rightreg = this.right.emit(output);
        int offset = {
            with (ArithmeticOpType) final switch (this.op)
            {
                case add:
                    return gen_int_stub!"add"(output);
                case sub:
                    return gen_int_stub!"sub"(output);
                case eq:
                    return gen_int_stub!"eq"(output);
            }
        }();
        int callreg = output.start_call_instr(offset, 2);
        output.add_call_reg_arg(leftreg);
        output.add_call_reg_arg(rightreg);
        return callreg;
    }

    mixin(GenerateThis);
    mixin(GenerateToString);
}

ASTExpression parseArithmetic(ref Parser parser, size_t level = 0)
{
    auto left = parser.parseExpressionLeaf;
    if (level <= 1)
    {
        parseAddSub(parser, left);
    }
    if (level == 0)
    {
        parseComparison(parser, left);
    }
    return left;
}

void parseAddSub(ref Parser parser, ref ASTExpression left)
{
    while (true)
    {
        if (parser.accept("+"))
        {
            auto right = parser.parseExpressionLeaf;
            left = new ASTArithmeticOp(ArithmeticOpType.add, left, right);
            continue;
        }
        if (parser.accept("-"))
        {
            auto right = parser.parseExpressionLeaf;
            left = new ASTArithmeticOp(ArithmeticOpType.sub, left, right);
            continue;
        }
        break;
    }
}

void parseComparison(ref Parser parser, ref ASTExpression left)
{
    if (parser.accept("=="))
    {
        auto right = parser.parseArithmetic(1);
        left = new ASTArithmeticOp(ArithmeticOpType.eq, left, right);
    }
}

class ASTCall : ASTExpression
{
    string function_;

    ASTExpression[] args;

    override Call compile(Namespace namespace)
    {
        auto function_ = cast(Function) namespace.lookup(this.function_);
        assert(function_);
        auto args = this.args.map!(a => a.compile(namespace)).array;
        return new Call(function_, args);
    }

    mixin(GenerateAll);
}

class Call : Expression
{
    Function function_;

    Expression[] args;

    override Type type()
    {
        return function_.ret;
    }

    override int emit(Generator output)
    {
        int fun_offset = declare(output, this.function_);
        int[] regs;
        foreach (arg; this.args)
        {
            regs ~= arg.emit(output);
        }
        int callreg = output.start_call_instr(fun_offset, cast(int) this.args.length);
        foreach (reg; regs)
        {
            output.add_call_reg_arg(reg);
        }
        return callreg;
    }

    mixin(GenerateThis);
    mixin(GenerateToString);
}

ASTExpression parseCall(ref Parser parser)
{
    with (parser)
    {
        begin;
        auto name = parser.parseIdentifier;
        if (!name || !accept("("))
        {
            revert;
            return null;
        }
        ASTExpression[] args;
        while (!accept(")"))
        {
            if (!args.empty)
                expect(",");
            args ~= parser.parseExpression;
        }
        commit;
        return new ASTCall(name, args);
    }
}

class Variable : ASTExpression
{
    string name;

    override Expression compile(Namespace namespace)
    out (result; result !is null)
    {
        return cast(Expression) namespace.lookup(name);
    }

    mixin(GenerateThis);
    mixin(GenerateToString);
}

class ASTLiteral : ASTExpression
{
    int value;

    override Literal compile(Namespace)
    {
        return new Literal(this.value);
    }

    mixin(GenerateAll);
}

class Literal : Expression
{
    int value;

    override int emit(Generator output)
    {
        return output.add_literal_instr(this.value);
    }

    override Type type()
    {
        return new Integer;
    }

    override string toString() const
    {
        import std.conv : to;

        return value.to!string;
    }

    mixin(GenerateThis);
}

class ArgExpr : Expression
{
    int index;

    Type type_;

    override int emit(Generator output)
    {
        return output.add_arg_instr(this.index);
    }

    override Type type()
    {
        return type_;
    }

    override string toString() const
    {
        import std.format : format;

        return format!"_%s"(this.index);
    }

    mixin(GenerateThis);
}

// reg contains pointer to type
class LoadRegExpr : Reference
{
    int reg;

    Type targetType;

    override Type type()
    {
        return this.targetType;
    }

    override int emit(Generator)
    {
        assert(false);
    }

    override int emitLocation(Generator)
    {
        return this.reg;
    }

    override string toString() const
    {
        import std.format : format;

        return format!"%%%s"(this.reg);
    }

    mixin(GenerateThis);
}

class StackFrame : Reference
{
    Type targetType;

    override Type type()
    {
        return this.targetType;
    }

    override int emit(Generator generator)
    {
        assert(false);
    }

    override int emitLocation(Generator generator)
    {
        return generator.frameReg;
    }

    override string toString() const
    {
        return "__frame";
    }

    mixin(GenerateThis);
}

class StructMember : Reference
{
    Reference base;

    int index;

    override Type type()
    {
        Type type = base.type();
        auto structType = cast(Struct) type;
        assert(structType);
        return structType.members[this.index];
    }

    override int emit(Generator output)
    {
        int locationReg = emitLocation(output);
        size_t offset = output.start_load_instr(locationReg);
        this.type().emit(output.defineSectionState.main_data);
        return output.end_load_instr(offset);
    }

    override int emitLocation(Generator output)
    {
        int reg = this.base.emitLocation(output);
        Type type = base.type();
        auto structType = cast(Struct) type;
        assert(structType);
        size_t offset = output.start_offset_instr(reg, this.index);
        structType.emit(output.defineSectionState.main_data);
        return output.end_offset_instr(offset);
    }

    override string toString() const
    {
        return format!"%s._%s"(this.base, this.index);
    }

    mixin(GenerateThis);
}

class Deref : Expression
{
    Expression base;

    override Type type()
    {
        Type superType = this.base.type();
        Pointer pointerType = cast(Pointer) superType;
        assert(pointerType, superType.toString);
        return pointerType.target;
    }

    override int emit(Generator output)
    {
        int reg = this.base.emit(output);
        size_t offset = output.start_load_instr(reg);
        this.type().emit(output.defineSectionState.main_data);
        return output.end_load_instr(offset);
    }

    mixin(GenerateThis);
}

struct RegValue
{
    int reg;

    Type type;
}

ASTExpression parseExpressionLeaf(ref Parser parser)
{
    with (parser)
    {
        if (auto name = parser.parseIdentifier)
        {
            return new Variable(name);
        }
        int i;
        if (parser.parseNumber(i))
        {
            return new ASTLiteral(i);
        }
        fail("Expression expected.");
        assert(false);
    }
}

class Namespace
{
    Namespace parent; // lexical parent

    abstract Symbol lookup(string name);

    mixin(GenerateThis);
}

T find(T)(Namespace namespace)
{
    while (namespace)
    {
        if (auto result = cast(T) namespace)
            return result;
        namespace = namespace.parent;
    }
    assert(false);
}

class FunctionScope : Namespace
{
    // union of structs
    @(This.Init!null)
    Type[][] traces;

    StructMember addFrameTrace(Type[] types)
    {
        traces ~= types;

        auto struct_ = new Struct(types);

        return new StructMember(new StackFrame(struct_), cast(int) types.length - 1);
    }

    size_t stackframeSize()
    {
        return this.traces
            .map!(a => (new Struct(a)).size)
            .reduce!max;
    }

    override Symbol lookup(string name)
    {
        return parent.lookup(name);
    }

    mixin(GenerateThis);
}

class VarDeclScope : Namespace
{
    Flag!"frameBase" frameBase; // base of function frame. all variables here are parameters.

    struct Variable
    {
        string name;

        Expression value;
    }

    @(This.Init!null)
    Variable[] declarations;

    Type[] enumerateDeclaredTypes()
    {
        auto myTypes = this.declarations.map!(a => a.value.type).array;

        if (frameBase)
            return myTypes;

        return parent.find!VarDeclScope.enumerateDeclaredTypes ~ myTypes;
    }

    Statement declare(string name, Expression value)
    {
        auto member = this.find!FunctionScope.addFrameTrace(enumerateDeclaredTypes ~ value.type());

        declarations ~= Variable(name, member);
        return new AssignStatement(member, value);
    }

    override Symbol lookup(string name)
    {
        foreach (var; this.declarations)
        {
            if (var.name == name)
                return var.value;
        }
        if (this.parent)
            return this.parent.lookup(name);
        return null;
    }

    mixin(GenerateThis);
}

class Module : Namespace
{
    struct Entry
    {
        string name;

        Symbol value;
    }

    @(This.Init!null)
    Entry[] entries;

    void add(string name, Symbol symbol)
    {
        this.entries ~= Entry(name, symbol);
    }

    override Symbol lookup(string name)
    {
        foreach (entry; this.entries)
        {
            if (entry.name == name)
                return entry.value;
        }
        if (this.parent)
            return this.parent.lookup(name);
        return null;
    }

    mixin(GenerateThis);
}

class BytecodeFile
{
    Generator generator;
    this()
    {
        this.generator = new Generator(alloc_bc_builder());
    }

    void define(Function fun, Namespace module_)
    {
        int declid = declare(this.generator, fun);
        assert(this.generator.defineSectionState is null);
        this.generator.defineSectionState = begin_define_section(this.generator.builder, declid);
        auto stackframe = new FunctionScope(module_);
        auto argscope = new VarDeclScope(stackframe, Yes.frameBase);
        Statement[] argAssignments;
        foreach (i, arg; fun.args)
        {
            auto argExpr = new ArgExpr(cast(int) i, arg.type);

            argAssignments ~= argscope.declare(arg.name, argExpr);
            arg.type.emit(this.generator.defineSectionState.main_data);
        }

        auto functionBody = fun.statement.compile(argscope);

        this.generator.start_block;
        generator.frameReg = generator.emit_alloc_instr(stackframe.stackframeSize);
        scope (success)
            generator.resetFrame;

        foreach (statement; argAssignments)
        {
            statement.emit(this.generator);
        }

        functionBody.emit(this.generator);
        end_define_section(this.generator.builder, this.generator.defineSectionState);
        this.generator.defineSectionState = null;
    }

    void writeTo(string filename)
    {
        static import std.file;

        std.file.write(filename, (cast(ubyte*) this.generator.builder.data.ptr)[0 .. this
                .generator.builder.data.length]);
    }
}

void main()
{
    string code = "int ack(int m, int n) {
        if (m == 0) { n = n + 1; return n; }
        if (n == 0) { int m1 = m - 1; return ack(m1, 1); }
        int m1 = m - 1; int n1 = n - 1;
        return ack(m1, ack(m, n1));
    }";
    auto parser = new Parser(code);
    auto fun = parser.parseFunction;
    // assert(parser.eof);

    writefln!"%s"(fun);

    auto toplevel = new Module(null);

    toplevel.add("ack", fun);
    auto output = new BytecodeFile;
    output.define(fun, toplevel);
    output.writeTo("ack.bc");
}
