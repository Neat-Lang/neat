module hello;

import backend.backend;
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
    abstract BackendType emit(BackendModule mod);

    abstract size_t size() const;

    override string toString() const
    {
        assert(false);
    }
}

class Integer : Type
{
    override BackendType emit(BackendModule mod)
    {
        return mod.intType;
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
    override BackendType emit(BackendModule mod)
    {
        return mod.voidType;
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

    override BackendType emit(BackendModule mod)
    {
        return mod.structType(this.members.map!(a => a.emit(mod)).array);
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

    override BackendType emit(BackendModule mod)
    {
        assert(false);
        // return mod.pointerType(target.emit(mod));
    }

    override string toString() const
    {
        return format!"%s*"(this.target);
    }
}

class Generator
{
    @NonNull
    BackendModule mod;

    BackendFunction fun;

    int numDeclarations;

    Nullable!Reg frameReg_;

    void frameReg(Reg reg)
    {
        this.frameReg_ = reg;
    }

    void resetFrame()
    {
        this.frameReg_.nullify;
    }

    Reg frameReg()
    {
        return this.frameReg_.get;
    }

    this(BackendModule mod, BackendFunction fun = null)
    {
        this.mod = mod;
        this.fun = fun;
    }

    void define(Function fun, Namespace module_)
    {
        assert(this.fun is null);
        this.fun = this.mod.define(
            fun.name,
            fun.ret.emit(this.mod),
            fun.args.map!(a => a.type.emit(this.mod)).array
        );
        auto stackframe = new FunctionScope(module_);
        auto argscope = new VarDeclScope(stackframe, Yes.frameBase);
        Statement[] argAssignments;
        foreach (i, arg; fun.args)
        {
            auto argExpr = new ArgExpr(cast(int) i, arg.type);

            argAssignments ~= argscope.declare(arg.name, argExpr);
        }

        auto functionBody = fun.statement.compile(argscope);

        frameReg = this.fun.alloca(stackframe.structType.emit(this.mod));
        scope (success)
            resetFrame;

        foreach (statement; argAssignments)
        {
            statement.emit(this);
        }

        functionBody.emit(this);
        this.fun = null;
    }
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
    Reg emit(Generator output);
}

interface Reference : Expression
{
    Reg emitLocation(Generator output);
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
        Reg reg = this.value.emit(output);

        output.fun.ret(reg);
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
        Reg reg = test.emit(output);

        auto tbrRecord = output.fun.testBranch(reg);

        tbrRecord.resolveThen(output.fun.blockIndex);
        then.emit(output);
        auto brRecord = output.fun.branch;

        // TODO else blk
        tbrRecord.resolveElse(output.fun.blockIndex);
        brRecord.resolve(output.fun.blockIndex);
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

        Reg target_reg = this.target.emitLocation(output);
        Reg value_reg = this.value.emit(output);

        output.fun.store(valueType.emit(output.mod), target_reg, value_reg);
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

    override Reg emit(Generator output)
    {
        Reg leftreg = this.left.emit(output);
        Reg rightreg = this.right.emit(output);
        string name = {
            with (ArithmeticOpType) final switch (this.op)
            {
                case add:
                    return "int_add";
                case sub:
                    return "int_sub";
                case eq:
                    return "int_eq";
            }
        }();
        return output.fun.call(name, [leftreg, rightreg]);
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

    override Reg emit(Generator output)
    {

        Reg[] regs;
        foreach (arg; this.args)
        {
            regs ~= arg.emit(output);
        }
        return output.fun.call(function_.name, regs);
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

    override Reg emit(Generator output)
    {
        return output.fun.literal(this.value);
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

    override Reg emit(Generator output)
    {
        return output.fun.arg(this.index);
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

    override Reg emit(Generator)
    {
        assert(false);
    }

    override Reg emitLocation(Generator)
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

    override Reg emit(Generator generator)
    {
        assert(false);
    }

    override Reg emitLocation(Generator generator)
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

    override Reg emit(Generator output)
    {
        Reg locationReg = emitLocation(output);

        return output.fun.load(this.type().emit(output.mod), locationReg);
    }

    override Reg emitLocation(Generator output)
    {
        Reg reg = this.base.emitLocation(output);

        return output.fun.fieldOffset(type.emit(output.mod), reg, this.index);
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

    override Reg emit(Generator output)
    {
        Reg reg = this.base.emit(output);

        return output.fun.load(this.type().emit(output.mod), reg);
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
    @(This.Init!null)
    Type[] variableTypes;

    StructMember declare(Type type)
    {
        variableTypes ~= type;

        return new StructMember(
            new StackFrame(structType),
            cast(int) variableTypes.length - 1);
    }

    Struct structType()
    {
        return new Struct(this.variableTypes);
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

    Statement declare(string name, Expression value)
    {
        auto member = this.find!FunctionScope.declare(value.type());

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

void main()
{
    import backend.interpreter : IpBackend;
    import backend.value : Value;

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

    auto backend = new IpBackend;
    auto interpreter = backend.createModule;

    interpreter.defineCallback("int_add", delegate Value(Value[] args)
    in (args.length == 2)
    {
        return Value.make!int(args[0].as!int + args[1].as!int);
    });
    interpreter.defineCallback("int_sub", delegate Value(Value[] args)
    in (args.length == 2)
    {
        return Value.make!int(args[0].as!int - args[1].as!int);
    });
    interpreter.defineCallback("int_eq", delegate Value(Value[] args)
    in (args.length == 2)
    {
        return Value.make!int(args[0].as!int == args[1].as!int);
    });

    auto output = new Generator(interpreter);

    output.define(fun, toplevel);

    for (int i = 0; i < 10; i++) {
        auto result = interpreter.call("ack", Value.make!int(3), Value.make!int(8));

        writefln!"ack(8, 3) = %s"(result.as!int);
    }
}
