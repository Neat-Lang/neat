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

interface ASTType
{
    Type compile(Namespace namespace);
}

class Type : Symbol
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

    override bool opEquals(const Object obj) const
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

    override bool opEquals(const Object obj) const
    {
        return cast(Void) obj !is null;
    }
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
        return size_t.sizeof;
    }

    override BackendType emit(BackendModule mod)
    {
        return mod.pointerType(target.emit(mod));
    }

    override string toString() const
    {
        return format!"%s*"(this.target);
    }

    override bool opEquals(const Object other) const
    {
        if (auto otherp = cast(Pointer) other)
        {
            return this.target == otherp.target;
        }
        return false;
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

            argAssignments ~= argscope.declare(arg.name, arg.type, argExpr);
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
        this.fun.ret(this.fun.voidLiteral);
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

    bool eof()
    {
        begin;
        strip;
        if (this.text.empty)
        {
            commit;
            return true;
        }
        revert;
        return false;
    }

    void fail(string msg)
    {
        assert(false, format!"at %s: %s"(this.text, msg));
    }

    void strip()
    {
        while (true)
        {
            this.text = this.text.strip;
            if (!this.text.startsWith("/*")) break;
            this.text = this.text["/*".length .. $];
            int commentLevel = 1;
            while (commentLevel > 0)
            {
                import std.algorithm : find;

                auto more = this.text.find("/*"), less = this.text.find("*/");

                if (more.empty && less.empty) fail("comment spans end of file");
                if (!less.empty && less.length > more.length)
                {
                    this.text = less["*/".length .. $];
                    commentLevel --;
                }
                if (!more.empty && more.length > less.length)
                {
                    this.text = more["/*".length .. $];
                    commentLevel ++;
                }
            }
        }
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

class ASTInteger : ASTType
{
    override Integer compile(Namespace) {
        return new Integer;
    }
}

class ASTVoid : ASTType
{
    override Void compile(Namespace) {
        return new Void;
    }
}

class ASTPointer : ASTType
{
    ASTType subType;

    override Type compile(Namespace namespace)
    {
        auto subType = this.subType.compile(namespace);

        return new Pointer(subType);
    }

    mixin(GenerateThis);
}

ASTType parseType(ref Parser parser)
{
    auto current = parseLeafType(parser);

    if (!current) return null;
    while (true)
    {
        if (parser.accept("*"))
        {
            current = new ASTPointer(current);
            continue;
        }
        break;
    }
    return current;
}

class NamedType : ASTType
{
    string name;

    override Type compile(Namespace namespace)
    {
        auto target = namespace.lookup(this.name);

        assert(cast(Type) target, format!"target for %s = %s"(this.name, target));
        return cast(Type) target;
    }

    mixin(GenerateThis);
}

ASTType parseLeafType(ref Parser parser)
{
    with (parser)
    {
        begin;

        auto identifier = parser.parseIdentifier;

        if (identifier == "int")
        {
            commit;
            return new ASTInteger;
        }

        if (identifier == "void")
        {
            commit;
            return new ASTVoid;
        }

        return new NamedType(identifier);
    }
}

struct ASTArgument
{
    @NonNull
    ASTType type;

    string name;

    mixin(GenerateAll);
}

class ASTFunction
{
    string name;

    @NonNull
    ASTType ret;

    ASTArgument[] args;

    bool declaration;

    ASTStatement statement;

    invariant (declaration || statement !is null);

    Function compile(Namespace namespace)
    {
        return new Function(
            this.name,
            this.ret.compile(namespace),
            this.args.map!(a => Argument(a.type.compile(namespace), a.name)).array,
            this.declaration,
            this.statement);
    }

    mixin(GenerateAll);
}

struct Argument
{
    @NonNull
    Type type;

    string name;

    mixin(GenerateAll);
}

class Function : Symbol
{
    string name;

    @NonNull
    Type ret;

    Argument[] args;

    bool declaration;

    ASTStatement statement;

    invariant (declaration || statement !is null);

    mixin(GenerateAll);
}

interface ASTStatement
{
    Statement compile(Namespace namespace);
}

interface Statement
{
    void emit(Generator output);
}

interface ASTExpression
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

ASTFunction parseFunction(ref Parser parser)
{
    with (parser)
    {
        begin;
        auto ret = parser.parseType;
        if (!ret)
        {
            revert;
            return null;
        }
        auto name = parser.parseIdentifier;
        expect("(");
        ASTArgument[] args;
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
            args ~= ASTArgument(argtype, argname);
        }
        auto stmt = parser.parseStatement;
        commit;
        return new ASTFunction(name, ret, args, false, stmt);
    }
}

class ASTStructDecl : ASTType
{
    struct Member
    {
        string name;

        ASTType type;

        mixin(GenerateThis);
    }

    string name;

    Member[] members;

    override Struct compile(Namespace namespace)
    {
        // TODO subscope
        return new Struct(name, members.map!(a => Struct.Member(a.name, a.type.compile(namespace))).array);
    }

    mixin(GenerateThis);
}

class Struct : Type
{
    struct Member
    {
        string name;

        Type type;

        mixin(GenerateThis);
    }

    string name;

    Member[] members;

    override BackendType emit(BackendModule mod)
    {
        return mod.structType(this.members.map!(a => a.type.emit(mod)).array);
    }

    override size_t size() const
    {
        return members.map!(a => a.type.size).sum;
    }

    override string toString() const
    {
        return format!"{ %(%s, %) }"(this.members);
    }

    mixin(GenerateThis);
}

ASTStructDecl parseStructDecl(ref Parser parser)
{
    with (parser)
    {
        begin;
        if (parser.parseIdentifier != "struct")
        {
            revert;
            return null;
        }
        auto name = parser.parseIdentifier;
        ASTStructDecl.Member[] members;
        expect("{");
        while (!accept("}"))
        {
            auto memberType = parser.parseType;
            assert(memberType, "expected member type");
            auto memberName = parser.parseIdentifier;
            assert(memberName, "expected member name");
            expect(";");
            members ~= ASTStructDecl.Member(memberName, memberType);
        }
        commit;
        return new ASTStructDecl(name, members);
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
        auto lhs = parser.parseExpressionLeaf;
        if (!lhs || !accept("="))
        {
            revert;
            return null;
        }
        auto expr = parser.parseExpression;
        expect(";");
        commit;
        return new ASTAssignStatement(lhs, expr);
    }
}

class ASTVarDeclStatement : ASTStatement
{
    string name;

    ASTType type;

    ASTExpression initial;

    override Statement compile(Namespace namespace)
    {
        if (this.initial)
        {
            auto initial = this.initial.compile(namespace);

            return namespace.find!VarDeclScope.declare(this.name, this.type.compile(namespace), initial);
        }
        else
        {
            return namespace.find!VarDeclScope.declare(this.name, this.type.compile(namespace));
        }
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
        if (!name)
        {
            revert;
            return null;
        }
        ASTExpression initial = null;
        if (accept("="))
        {
            initial = parser.parseExpression;
            assert(initial);
        }
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
    if (auto stmt = parser.parseWhile)
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
    return parser.parseArithmetic;
}

enum ArithmeticOpType
{
    add,
    sub,
    mul,
    eq,
    gt,
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
                case mul:
                    return "int_mul";
                case eq:
                    return "int_eq";
                case gt:
                    return "int_gt";
            }
        }();
        return output.fun.call(output.mod.intType, name, [leftreg, rightreg]);
    }

    mixin(GenerateThis);
    mixin(GenerateToString);
}

ASTExpression parseArithmetic(ref Parser parser, size_t level = 0)
{
    auto left = parser.parseExpressionLeaf;

    if (level <= 2)
    {
        parseMul(parser, left);
    }
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

void parseMul(ref Parser parser, ref ASTExpression left)
{
    while (true)
    {
        if (parser.accept("*"))
        {
            auto right = parser.parseExpressionLeaf;
            left = new ASTArithmeticOp(ArithmeticOpType.mul, left, right);
            continue;
        }
        break;
    }
}

void parseAddSub(ref Parser parser, ref ASTExpression left)
{
    while (true)
    {
        if (parser.accept("+"))
        {
            auto right = parser.parseArithmetic(2);
            left = new ASTArithmeticOp(ArithmeticOpType.add, left, right);
            continue;
        }
        if (parser.accept("-"))
        {
            auto right = parser.parseArithmetic(2);
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
    if (parser.accept(">"))
    {
        auto right = parser.parseArithmetic(1);
        left = new ASTArithmeticOp(ArithmeticOpType.gt, left, right);
    }
}

class ASTWhile : ASTStatement
{
    ASTExpression cond;

    ASTStatement body_;

    override WhileLoop compile(Namespace namespace)
    {
        auto subscope = new VarDeclScope(namespace, No.frameBase);
        auto condExpr = this.cond.compile(subscope);
        auto bodyStmt = this.body_.compile(subscope);

        return new WhileLoop(condExpr, bodyStmt);
    }

    mixin(GenerateAll);
}

class WhileLoop : Statement
{
    Expression cond;

    Statement body_;

    override void emit(Generator output)
    {
        /**
         * start:
         * if (cond) goto body; else goto end;
         * body:
         * goto start
         * end:
         */
        auto start = output.fun.branch; // start:
        auto startIndex = output.fun.blockIndex;

        start.resolve(startIndex);

        auto condReg = cond.emit(output);
        auto condBranch = output.fun.testBranch(condReg); // if (cond)

        condBranch.resolveThen(output.fun.blockIndex); // goto body
        body_.emit(output);
        output.fun.branch().resolve(startIndex); // goto start
        condBranch.resolveElse(output.fun.blockIndex); // else goto end
    }

    mixin(GenerateAll);
}

ASTWhile parseWhile(ref Parser parser)
{
    with (parser)
    {
        begin;
        auto stmt = parser.parseIdentifier;
        if (stmt != "while" || !accept("("))
        {
            revert;
            return null;
        }
        ASTExpression cond = parser.parseExpression;
        expect(")");
        ASTStatement body_ = parser.parseStatement;

        commit;
        return new ASTWhile(cond, body_);
    }
}

class ASTCall : ASTExpression
{
    string function_;

    ASTExpression[] args;

    override Call compile(Namespace namespace)
    {
        auto function_ = cast(Function) namespace.lookup(this.function_);
        assert(function_, "unknown call target " ~ this.function_);
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
        return output.fun.call(type.emit(output.mod), function_.name, regs);
    }

    mixin(GenerateThis);
    mixin(GenerateToString);
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
        return output.fun.intLiteral(this.value);
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
        return structType.members[this.index].type;
    }

    override Reg emit(Generator output)
    {
        Reg locationReg = emitLocation(output);

        return output.fun.load(this.type().emit(output.mod), locationReg);
    }

    override Reg emitLocation(Generator output)
    {
        Reg reg = this.base.emitLocation(output);

        return output.fun.fieldOffset(base.type.emit(output.mod), reg, this.index);
    }

    override string toString() const
    {
        return format!"%s._%s"(this.base, this.index);
    }

    mixin(GenerateThis);
}

class ASTDereference : ASTExpression
{
    ASTExpression base;

    override Dereference compile(Namespace namespace)
    {
        return new Dereference(base.compile(namespace));
    }

    mixin(GenerateThis);
}

class Dereference : Reference
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
        Reg reg = emitLocation(output);

        return output.fun.load(this.type().emit(output.mod), reg);
    }

    override Reg emitLocation(Generator output)
    {
        return this.base.emit(output);
    }

    override string toString() const
    {
        return format!"*%s"(this.base);
    }

    mixin(GenerateThis);
}

class ASTReference : ASTExpression
{
    ASTExpression base;

    override ReferenceExpression compile(Namespace namespace)
    {
        auto baseExpression = base.compile(namespace);
        assert(cast(Reference) baseExpression !is null);

        return new ReferenceExpression(cast(Reference) baseExpression);
    }

    mixin(GenerateThis);
}

class ReferenceExpression : Expression
{
    Reference base;

    override Type type()
    {
        Type superType = this.base.type();
        return new Pointer(superType);
    }

    override Reg emit(Generator output)
    {
        return base.emitLocation(output);
    }

    override string toString() const
    {
        return format!"&%s"(this.base);
    }

    mixin(GenerateThis);
}

ASTCall parseCall(ref Parser parser, ASTExpression base)
{
    with (parser)
    {
        begin;
        if (!accept("("))
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
        // TODO method and pointer calls
        assert(cast(Variable) base);
        return new ASTCall((cast(Variable) base).name, args);
    }
}

class ASTStructMember : ASTExpression
{
    ASTExpression base;

    string member;

    override StructMember compile(Namespace namespace)
    {
        auto base = this.base.compile(namespace);
        while (cast(Pointer) base.type) {
            base = new Dereference(base);
        }
        assert(cast(Reference) base, "TODO struct member of value");
        auto structType = cast(Struct) base.type;
        assert(structType, "expected struct type for member");
        auto memberOffset = structType.members.countUntil!(a => a.name == this.member);
        assert(memberOffset != -1, "no such member " ~ this.member);

        return new StructMember(cast(Reference) base, cast(int) memberOffset);
    }

    mixin(GenerateThis);
}

ASTExpression parseMember(ref Parser parser, ASTExpression base)
{
    with (parser)
    {
        begin;
        if (!accept("."))
        {
            revert;
            return null;
        }
        auto name = parser.parseIdentifier;
        assert(name, "member expected");
        commit;
        return new ASTStructMember(base, name);
    }
}

ASTExpression parseExpressionLeaf(ref Parser parser)
{
    with (parser)
    {
        if (accept("*"))
        {
            auto next = parser.parseExpressionLeaf;

            assert(next !is null);
            return new ASTDereference(next);
        }
        if (accept("&"))
        {
            auto next = parser.parseExpressionLeaf;

            assert(next !is null);
            return new ASTReference(next);
        }
        auto currentExpr = parser.parseExpressionBase;
        assert(currentExpr);
        while (true)
        {
            if (auto expr = parser.parseCall(currentExpr))
            {
                currentExpr = expr;
                continue;
            }
            if (auto expr = parser.parseMember(currentExpr))
            {
                currentExpr = expr;
                continue;
            }
            break;
        }
        return currentExpr;
    }
}

ASTExpression parseExpressionBase(ref Parser parser)
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
    parser.fail("Base expression expected.");
    assert(false);
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
        return new Struct(null, this.variableTypes.map!(a => Struct.Member(null, a)).array);
    }

    override Symbol lookup(string name)
    {
        return parent.lookup(name);
    }

    mixin(GenerateThis);
}

class PointerCast : Expression
{
    Expression value;

    Type target;

    override Type type()
    {
        return this.target;
    }

    override Reg emit(Generator output)
    {
        return this.value.emit(output); // pointer's a pointer
    }

    mixin(GenerateThis);
}

Expression implicitConvertTo(Expression from, Type to)
{
    if (from.type == to) return from;
    // void* casts to any pointer
    if (cast(Pointer) to && from.type == new Pointer(new Void))
    {
        return new PointerCast(from, to);
    }
    assert(false, format!"todo: cast(%s) %s"(to, from.type));
}

class NoopStatement : Statement
{
    override void emit(Generator)
    {
    }
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

    Statement declare(string name, Type type, Expression value)
    {
        auto member = this.find!FunctionScope.declare(type);

        declarations ~= Variable(name, member);
        return new AssignStatement(member, value.implicitConvertTo(type));
    }

    Statement declare(string name, Type type)
    {
        auto member = this.find!FunctionScope.declare(type);

        declarations ~= Variable(name, member);
        return new NoopStatement;
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

    void emit(Generator generator)
    in (generator.fun is null)
    {
        foreach (entry; entries)
        {
            if (auto fun = cast(Function) entry.value)
                if (!fun.declaration)
                    generator.define(fun, this);
        }
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

Module parseModule(ref Parser parser)
{
    auto module_ = new Module(null);

    while (!parser.eof)
    {
        auto strct = parser.parseStructDecl;

        if (strct) {
            module_.add(strct.name, strct.compile(module_));
            continue;
        }

        auto fun = parser.parseFunction;

        if (fun) {
            module_.add(fun.name, fun.compile(module_));
            continue;
        }

        parser.fail("couldn't parse function or struct");
    }
    return module_;
}

void main()
{
    import backend.interpreter : IpBackend;
    import std.file : readText;

    string code = readText("hello.cx");
    auto parser = new Parser(code);
    auto toplevel = parser.parseModule;

    auto backend = new IpBackend;
    auto module_ = backend.createModule;

    defineRuntime(module_, toplevel);

    auto output = new Generator(module_);

    toplevel.emit(output);

    writefln!"module:\n%s"(module_);

    module_.call("main", null, null);
}

void defineRuntime(BackendModule backModule, Module frontModule)
{
    import backend.interpreter : IpBackendModule;

    frontModule.addFunction(new Function("assert", new Void, [Argument(new Integer, "")], true, null));
    frontModule.addFunction(new Function("malloc", new Pointer(new Void), [Argument(new Integer, "")], true, null));

    auto ipModule = cast(IpBackendModule) backModule;

    ipModule.defineCallback("int_add", delegate void(void[] ret, void[][] args)
    in (args.length == 2)
    {
        ret.as!int = args[0].as!int + args[1].as!int;
    });
    ipModule.defineCallback("int_sub", delegate void(void[] ret, void[][] args)
    in (args.length == 2)
    {
        ret.as!int = args[0].as!int - args[1].as!int;
    });
    ipModule.defineCallback("int_mul", delegate void(void[] ret, void[][] args)
    in (args.length == 2)
    {
        ret.as!int = args[0].as!int * args[1].as!int;
    });
    ipModule.defineCallback("int_eq", delegate void(void[] ret, void[][] args)
    in (args.length == 2)
    {
        ret.as!int = args[0].as!int == args[1].as!int;
    });
    ipModule.defineCallback("int_gt", delegate void(void[] ret, void[][] args)
    in (args.length == 2)
    {
        ret.as!int = args[0].as!int > args[1].as!int;
    });
    ipModule.defineCallback("assert", delegate void(void[] ret, void[][] args)
    in (args.length == 1)
    {
        assert(args[0].as!int, "Assertion failed!");
    });
    ipModule.defineCallback("malloc", delegate void(void[] ret, void[][] args)
    in (args.length == 1)
    {
        import core.stdc.stdlib : malloc;

        ret.as!(void*) = malloc(args[0].as!int);
    });
}

private template as(T) {
    ref T as(Arg)(Arg arg) { return (cast(T[]) arg)[0]; }
}

void addFunction(Module module_, Function function_)
{
    module_.add(function_.name, function_);
}
