module main;

import backend.backend;
import boilerplate;
import std.algorithm;
import std.conv : to;
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

class Character : Type
{
    override BackendType emit(BackendModule mod)
    {
        return mod.charType;
    }

    override size_t size() const
    {
        return 1;
    }

    override string toString() const
    {
        return "char";
    }

    override bool opEquals(const Object obj) const
    {
        return cast(Character) obj !is null;
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

    mixin(GenerateThis);
}

class FunctionPointer : Type
{
    Type ret;

    Type[] args;

    override size_t size() const
    {
        return size_t.sizeof;
    }

    override BackendType emit(BackendModule mod)
    {
        return mod.funcPointerType(
            ret.emit(mod),
            args.map!(a => a.emit(mod)).array);
    }

    override string toString() const
    {
        return format!"%s function(%(%s, %))"(this.ret, this.args);
    }

    override bool opEquals(const Object other) const
    {
        if (auto otherp = cast(FunctionPointer) other)
        {
            return this.ret == otherp.ret && this.args == otherp.args;
        }
        return false;
    }

    mixin(GenerateThis);
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

string parseIdentifier(ref Parser parser, string additionalCharacters = "")
{
    with (parser)
    {
        begin;
        strip;
        if (text.empty || (!text.front.isAlpha && text.front != '_' && !additionalCharacters.canFind(text.front)))
        {
            revert;
            return null;
        }
        string identifier;
        while (!text.empty && (text.front.isAlphaNum || text.front == '_' || additionalCharacters.canFind(text.front)))
        {
            identifier ~= text.front;
            text.popFront;
        }
        commit;
        return identifier;
    }
}


bool acceptIdentifier(ref Parser parser, string identifier)
{
    with (parser)
    {
        begin;
        if (parser.parseIdentifier != identifier)
        {
            revert;
            return false;
        }
        commit;
        return true;
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

class ASTCharType : ASTType
{
    override Character compile(Namespace) {
        return new Character;
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

class ASTFunctionPointer : ASTType
{
    ASTType ret;

    ASTType[] args;

    override Type compile(Namespace namespace)
    {
        auto ret = this.ret.compile(namespace);
        auto args = this.args.map!(a => a.compile(namespace)).array;

        return new FunctionPointer(ret, args);
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
        with (parser)
        {
            begin;
            if (parser.parseIdentifier == "function")
            {
                expect("(");
                ASTType[] args;
                while (!accept(")"))
                {
                    if (!args.empty)
                    {
                        if (!accept(","))
                        {
                            fail("',' or ')' expected");
                        }
                    }
                    auto argType = parser.parseType;
                    assert(argType);
                    args ~= argType;
                }
                commit;
                current = new ASTFunctionPointer(current, args);
                continue;
            }
            revert;
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

        if (identifier == "char")
        {
            commit;
            return new ASTCharType;
        }

        return new NamedType(identifier);
    }
}

struct ASTArgument
{
    string name;

    @NonNull
    ASTType type;

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
            this.args.map!(a => Argument(a.name, a.type.compile(namespace))).array,
            this.declaration,
            this.statement);
    }

    mixin(GenerateAll);
}

struct Argument
{
    string name;

    @NonNull
    Type type;

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

    void emit(Generator generator, Namespace module_)
    {
        assert(generator.fun is null);
        generator.fun = generator.mod.define(
            name,
            ret.emit(generator.mod),
            args.map!(a => a.type.emit(generator.mod)).array
        );
        auto stackframe = new FunctionScope(module_);
        auto argscope = new VarDeclScope(stackframe, Yes.frameBase);
        Statement[] argAssignments;
        foreach (i, arg; args)
        {
            auto argExpr = new ArgExpr(cast(int) i, arg.type);

            argAssignments ~= argscope.declare(arg.name, arg.type, argExpr);
        }

        auto functionBody = statement.compile(argscope);

        generator.frameReg = generator.fun.alloca(stackframe.structType.emit(generator.mod));
        scope (success)
            generator.resetFrame;

        foreach (statement; argAssignments)
        {
            statement.emit(generator);
        }

        functionBody.emit(generator);
        generator.fun.ret(generator.fun.voidLiteral);
        generator.fun = null;
    }

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

interface ASTSymbol
{
    Symbol compile(Namespace namespace);
}

Expression beExpression(Symbol symbol)
{
    if (auto expr = cast(Expression) symbol)
    {
        return expr;
    }
    assert(false, format!"expected expression, not %s"(symbol));
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

ASTArgument[] parseIdentifierList(ref Parser parser)
{
    with (parser)
    {
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
            args ~= ASTArgument(argname, argtype);
        }
        return args;
    }
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
        ASTArgument[] args = parser.parseIdentifierList;
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
            if (!memberType) parser.fail("expected member type");
            auto memberName = parser.parseIdentifier;
            if (!memberName) parser.fail("expected member name");
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
    ASTSymbol value;

    override ReturnStatement compile(Namespace namespace)
    {
        return new ReturnStatement(value.compile(namespace).beExpression);
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
    ASTSymbol test;
    ASTStatement then;

    override IfStatement compile(Namespace namespace)
    {
        auto ifscope = new VarDeclScope(namespace, No.frameBase);
        auto test = this.test.compile(ifscope);
        auto then = this.then.compile(ifscope);

        return new IfStatement(test.beExpression, then);
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
    ASTSymbol target;

    ASTSymbol value;

    override AssignStatement compile(Namespace namespace)
    {
        auto target = this.target.compile(namespace);
        auto value = this.value.compile(namespace);
        auto targetref = cast(Reference) target;
        assert(targetref, "target of assignment must be a reference");
        return new AssignStatement(targetref, value.beExpression.implicitConvertTo(targetref.type()));
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
        commit;
        return new ASTAssignStatement(lhs, expr);
    }
}

ASTAssignStatement parseAssignStatement(ref Parser parser)
{
    with (parser)
    {
        if (auto ret = parser.parseAssignment)
        {
            expect(";");
            return ret;
        }
        return null;
    }
}

class ASTVarDeclStatement : ASTStatement
{
    string name;

    ASTType type;

    ASTSymbol initial;

    override Statement compile(Namespace namespace)
    {
        if (this.initial)
        {
            auto initial = this.initial.compile(namespace);

            return namespace.find!VarDeclScope.declare(this.name, this.type.compile(namespace), initial.beExpression);
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
        ASTSymbol initial = null;
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
    ASTSymbol value;

    override Statement compile(Namespace namespace)
    {
        return new ExprStatement(this.value.compile(namespace).beExpression);
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
    if (auto stmt = parser.parseFor)
        return stmt;
    if (auto stmt = parser.parseScope)
        return stmt;
    if (auto stmt = parser.parseAssignStatement)
        return stmt;
    if (auto stmt = parser.parseVarDecl)
        return stmt;
    if (auto stmt = parser.parseExprStatement)
        return stmt;
    parser.fail("statement expected");
    assert(false);
}

ASTSymbol parseExpression(ref Parser parser)
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
    lt,
    ge,
    le,
}

class ASTArithmeticOp : ASTSymbol
{
    ArithmeticOpType op;
    ASTSymbol left;
    ASTSymbol right;

    override ArithmeticOp compile(Namespace namespace)
    {
        return new ArithmeticOp(op, left.compile(namespace).beExpression, right.compile(namespace).beExpression);
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
                    return "cxruntime_int_add";
                case sub:
                    return "cxruntime_int_sub";
                case mul:
                    return "cxruntime_int_mul";
                case eq:
                    return "cxruntime_int_eq";
                case gt:
                    return "cxruntime_int_gt";
                case lt:
                    return "cxruntime_int_lt";
                case ge:
                    return "cxruntime_int_ge";
                case le:
                    return "cxruntime_int_le";
            }
        }();
        return output.fun.call(output.mod.intType, name, [leftreg, rightreg]);
    }

    mixin(GenerateThis);
    mixin(GenerateToString);
}

ASTSymbol parseArithmetic(ref Parser parser, size_t level = 0)
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

void parseMul(ref Parser parser, ref ASTSymbol left)
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

void parseAddSub(ref Parser parser, ref ASTSymbol left)
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

void parseComparison(ref Parser parser, ref ASTSymbol left)
{
    if (parser.accept("=="))
    {
        auto right = parser.parseArithmetic(1);
        left = new ASTArithmeticOp(ArithmeticOpType.eq, left, right);
    }
    if (parser.accept(">="))
    {
        auto right = parser.parseArithmetic(1);
        left = new ASTArithmeticOp(ArithmeticOpType.ge, left, right);
    }
    if (parser.accept(">"))
    {
        auto right = parser.parseArithmetic(1);
        left = new ASTArithmeticOp(ArithmeticOpType.gt, left, right);
    }
    if (parser.accept("<="))
    {
        auto right = parser.parseArithmetic(1);
        left = new ASTArithmeticOp(ArithmeticOpType.le, left, right);
    }
    if (parser.accept("<"))
    {
        auto right = parser.parseArithmetic(1);
        left = new ASTArithmeticOp(ArithmeticOpType.lt, left, right);
    }
}

class ASTWhile : ASTStatement
{
    ASTSymbol cond;

    ASTStatement body_;

    override WhileLoop compile(Namespace namespace)
    {
        auto subscope = new VarDeclScope(namespace, No.frameBase);
        auto condExpr = this.cond.compile(subscope);
        auto bodyStmt = this.body_.compile(subscope);

        return new WhileLoop(condExpr.beExpression, bodyStmt);
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
        if (!parser.acceptIdentifier("while"))
        {
            return null;
        }
        expect("(");
        ASTSymbol cond = parser.parseExpression;
        expect(")");
        ASTStatement body_ = parser.parseStatement;

        return new ASTWhile(cond, body_);
    }
}

class ASTForLoop : ASTStatement
{
    ASTVarDeclStatement declareLoopVar;

    ASTSymbol condition;

    ASTStatement step;

    ASTStatement body_;

    Statement compile(Namespace namespace)
    {
        /*
         * hack until break/continue:
         * for (decl; test; step) body
         * decl; while (test) { body; step; }
         */
        auto forscope = new VarDeclScope(namespace, No.frameBase);
        auto decl = declareLoopVar.compile(forscope);
        auto body_ = this.body_.compile(forscope);
        auto step = this.step.compile(forscope);
        auto loop = new WhileLoop(condition.compile(forscope).beExpression, new SequenceStatement([body_, step]));

        return new SequenceStatement([decl, loop]);
    }

    mixin(GenerateThis);
}

ASTForLoop parseFor(ref Parser parser)
{
    with (parser)
    {
        if (!parser.acceptIdentifier("for"))
        {
            return null;
        }
        expect("(");
        auto varDecl = parser.parseVarDecl;
        auto condition = parser.parseExpression;
        expect(";");
        auto step = parser.parseAssignment;
        expect(")");
        auto body_ = parser.parseStatement;

        return new ASTForLoop(varDecl, condition, step, body_);
    }
}

Expression call(Symbol target, Expression[] args)
{
    if (auto function_ = cast(Function) target)
    {
        return new Call(function_, args);
    }
    if (auto method = cast(ClassMethod) target)
    {
        return new FuncPtrCall(method.funcPtr, [method.thisPtr] ~ args);
    }
    auto expr = cast(Expression) target;
    if (expr && cast(FunctionPointer) expr.type)
    {
        return new FuncPtrCall(expr, args);
    }
    assert(false, format!"unknown call target %s (%s?)"(target, expr ? expr.type : null));
}

class ASTCall : ASTSymbol
{
    ASTSymbol target;

    ASTSymbol[] args;

    override Expression compile(Namespace namespace)
    {
        auto target = this.target.compile(namespace);
        auto args = this.args.map!(a => a.compile(namespace).beExpression).array;

        return target.call(args);
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

class FuncPtrCall : Expression
{
    Expression funcPtr;

    Expression[] args;

    override Type type()
    {
        return (cast(FunctionPointer) funcPtr.type).ret;
    }

    override Reg emit(Generator output)
    {
        Reg[] regs;
        foreach (arg; this.args)
        {
            regs ~= arg.emit(output);
        }
        return output.fun.callFuncPtr(
            type.emit(output.mod), funcPtr.emit(output), regs);
    }

    mixin(GenerateThis);
    mixin(GenerateToString);
}

class Variable : ASTSymbol
{
    string name;

    override Symbol compile(Namespace namespace)
    out (result; result !is null)
    {
        auto ret = namespace.lookup(name);
        assert(ret, format!"%s not found"(name));
        return ret;
    }

    mixin(GenerateThis);
    mixin(GenerateToString);
}

class ASTLiteral : ASTSymbol
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

class ASTDereference : ASTSymbol
{
    ASTSymbol base;

    override Dereference compile(Namespace namespace)
    {
        return new Dereference(base.compile(namespace).beExpression);
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

class ASTReference : ASTSymbol
{
    ASTSymbol base;

    override Expression compile(Namespace namespace)
    {
        // &function
        if (auto var = cast(Variable) base)
        {
            auto target = namespace.lookup(var.name);

            if (auto fun = cast(Function) target)
            {
                return new FunctionReference(fun);
            }
        }
        auto baseExpression = base.compile(namespace);
        assert(cast(Reference) baseExpression !is null);

        return new ReferenceExpression(cast(Reference) baseExpression);
    }

    mixin(GenerateThis);
}

class FunctionReference : Expression
{
    Function fun;

    override FunctionPointer type()
    {
        return new FunctionPointer(fun.ret, fun.args.map!(a => a.type).array);
    }

    override Reg emit(Generator output)
    {
        return output.fun.getFuncPtr(this.fun.name);
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

ASTSymbol[] parseSymbolList(ref Parser parser)
{
    with (parser)
    {
        ASTSymbol[] args;
        while (!accept(")"))
        {
            if (!args.empty)
                expect(",");
            args ~= parser.parseExpression;
        }
        return args;
    }
}

ASTCall parseCall(ref Parser parser, ASTSymbol base)
{
    with (parser)
    {
        begin;
        if (!accept("("))
        {
            revert;
            return null;
        }
        ASTSymbol[] args = parser.parseSymbolList;
        commit;
        return new ASTCall(base, args);
    }
}

class ClassMethod : Symbol
{
    Expression funcPtr;

    Expression thisPtr;

    mixin(GenerateThis);
}

Symbol accessMember(Symbol base, string member)
{
    if (cast(Expression) base)
    {
        auto baseExpr = base.beExpression;

        while (cast(Pointer) baseExpr.type) {
            baseExpr = new Dereference(baseExpr);
        }
        if (auto structType = cast(Struct) baseExpr.type)
        {
            assert(cast(Reference) baseExpr, "TODO struct member of value");
            auto memberOffset = structType.members.countUntil!(a => a.name == member);
            assert(memberOffset != -1, "no such member " ~ member);
            return new StructMember(cast(Reference) baseExpr, cast(int) memberOffset);
        }
        if (auto classType = cast(Class) baseExpr.type)
        {
            import std.algorithm : find;

            auto methodOffset = classType.vtable.countUntil!(a => a.name == member);
            auto asStructPtr = new PointerCast(new Pointer(classType.dataStruct), baseExpr);
            if (methodOffset != -1)
            {
                auto classInfo = new Dereference(new PointerCast(
                    new Pointer(classType.classInfoStruct), new StructMember(new Dereference(asStructPtr), 0)));
                // TODO dereference-into-symbol so we can '&' it again
                auto funcPtr = new StructMember(classInfo, cast(int) methodOffset);
                return new ClassMethod(funcPtr, baseExpr);
            }
            auto memberOffset = classType.visibleMembers.find!(a => a.name == member);
            assert(!memberOffset.empty, format!"no such member %s in %s"(member, classType));
            return new StructMember(
                new Dereference(asStructPtr),
                cast(int) memberOffset.front.index,
            );
        }

        assert(false, format!"expected struct/class type for member, not %s of %s"(baseExpr, baseExpr.type));
    }
    assert(false, format!"expected expression for member access, not %s"(base));
}

class ASTMember : ASTSymbol
{
    ASTSymbol base;

    string member;

    override Symbol compile(Namespace namespace)
    {
        auto base = this.base.compile(namespace);

        return base.accessMember(this.member);
    }

    mixin(GenerateThis);
}

ASTSymbol parseMember(ref Parser parser, ASTSymbol base)
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
        return new ASTMember(base, name);
    }
}

class ASTIndexAccess : ASTSymbol
{
    ASTSymbol base;

    ASTSymbol index;

    override Expression compile(Namespace namespace)
    {
        auto base = this.base.compile(namespace).beExpression;
        auto index = this.index.compile(namespace).beExpression;

        assert(cast(Pointer) base.type, "expected pointer for index base");
        assert(cast(Integer) index.type, "expected int for index value");

        auto int_mul = new Function("cxruntime_int_mul",
            new Integer,
            [Argument("", new Integer), Argument("", new Integer)],
            true, null);
        auto ptr_offset = new Function("ptr_offset",
            new Pointer(new Void),
            [Argument("", new Pointer(new Void)), Argument("", new Integer)],
            true, null);
        auto offset = new Call(int_mul, [index, new Literal(cast(int) (cast(Pointer) base.type).target.size)]);

        return new Dereference(new PointerCast(base.type, new Call(ptr_offset, [base, offset])));
    }

    mixin(GenerateThis);
}

ASTSymbol parseIndex(ref Parser parser, ASTSymbol base)
{
    with (parser)
    {
        begin;
        if (!accept("["))
        {
            revert;
            return null;
        }
        auto index = parser.parseExpression;
        assert(index, "index expected");
        expect("]");
        commit;
        return new ASTIndexAccess(base, index);
    }
}

class ASTNewClassExpression : ASTSymbol
{
    ASTType type;

    Nullable!(ASTSymbol[]) args;

    override Expression compile(Namespace namespace)
    {
        auto type = this.type.compile(namespace);
        auto classType = cast(Class) type;
        auto classptr = new NewClassExpression(classType);

        if (args.isNull)
        {
            return classptr;
        }
        Expression[] argExpressions = this.args.get.map!(a => a.compile(namespace).beExpression).array;
        assert(classType, format!"expected new <class>, not %s"(type));
        return new CallCtorExpression(classptr, argExpressions);
    }

    mixin(GenerateThis);
}

class RegExpr : Expression
{
    Type type_;

    Reg reg;

    override Type type()
    {
        return this.type_;
    }

    override Reg emit(Generator output)
    {
        return this.reg;
    }

    mixin(GenerateThis);
}

class CallCtorExpression : Expression
{
    Expression classptr;

    Expression[] args;

    override Type type()
    {
        return this.classptr.type;
    }

    override Reg emit(Generator output)
    {
        auto reg = this.classptr.emit(output);
        auto expr = new RegExpr(type, reg);

        expr.accessMember("this").call(this.args).emit(output);
        return reg;
    }

    mixin(GenerateThis);
}

class NewClassExpression : Expression
{
    Class classType;

    override Type type()
    {
        return this.classType;
    }

    override Reg emit(Generator output)
    {
        // oh boy.
        auto classInfoStruct = this.classType.classInfoStruct;
        auto classDataStruct = this.classType.dataStruct;
        auto voidp = (new Pointer(new Void)).emit(output.mod);
        auto classInfoPtr = output.fun.call(voidp, "malloc", [output.fun.intLiteral(cast(int) classInfoStruct.size)]);
        foreach (i, method; classType.vtable)
        {
            auto funcPtr = method.funcPtrType;
            auto target = output.fun.fieldOffset(classInfoStruct.emit(output.mod), classInfoPtr, cast(int) i);
            auto src = output.fun.getFuncPtr(method.mangle);
            output.fun.store(funcPtr.emit(output.mod), target, src);
        }
        auto classPtr = output.fun.call(voidp, "malloc", [output.fun.intLiteral(cast(int) classDataStruct.size)]);
        auto classInfoTarget = output.fun.fieldOffset(classDataStruct.emit(output.mod), classPtr, 0);
        output.fun.store(voidp, classInfoTarget, classInfoPtr);

        return classPtr;
    }

    mixin(GenerateThis);
}

class ASTAllocPtrExpression : ASTSymbol
{
    ASTType type;

    ASTSymbol size;

    override Expression compile(Namespace namespace)
    {
        auto type = this.type.compile(namespace);
        auto size = this.size.compile(namespace).beExpression;
        auto malloc = new Function("malloc",
            new Pointer(new Void),
            [Argument("", new Integer)],
            true, null);
        auto int_mul = new Function("cxruntime_int_mul",
            new Integer,
            [Argument("a", new Integer), Argument("b", new Integer)],
            true, null);
        auto bytesize = new Call(int_mul, [size, new Literal(cast(int) type.size)]);

        return new Call(malloc, [bytesize]);
    }

    mixin(GenerateThis);
}

ASTSymbol parseExpressionLeaf(ref Parser parser)
{
    with (parser)
    {
        if (accept("\""))
        {
            return parser.parseStringLiteral("\"");
        }
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
        if (parser.acceptIdentifier("new"))
        {
            auto type = parser.parseType;
            Nullable!(ASTSymbol[]) args;
            if (accept("("))
            {
                args = parser.parseSymbolList;
            }

            return new ASTNewClassExpression(type, args);
        }
        if (parser.acceptIdentifier("_alloc"))
        {
            expect("(");
            auto type = parser.parseType;
            expect(",");
            auto size = parser.parseExpression;
            expect(")");
            return new ASTAllocPtrExpression(type, size);
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
            if (auto expr = parser.parseIndex(currentExpr))
            {
                currentExpr = expr;
                break;
            }
            break;
        }
        return currentExpr;
    }
}

ASTStringLiteral parseStringLiteral(ref Parser parser, string endMarker)
{
    import std.exception : enforce;

    string str;
    with (parser)
    {
        while (!text.startsWith(endMarker))
        {
            if (text.empty)
            {
                fail("expected end of string, got end of file");
            }

            str ~= text.front;
            text.popFront;
        }
        accept(endMarker).enforce;

        return new ASTStringLiteral(str);
    }
}

class ASTStringLiteral : ASTSymbol
{
    string text;

    StringLiteral compile(Namespace)
    {
        return new StringLiteral(text);
    }

    mixin(GenerateThis);
}

class StringLiteral : Expression
{
    string text;

    override Type type()
    {
        return new Pointer(new Character);
    }

    override Reg emit(Generator output)
    {
        return output.fun.stringLiteral(this.text);
    }

    mixin(GenerateThis);
}

ASTSymbol parseExpressionBase(ref Parser parser)
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
    Type target;

    Expression value;

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
        return new PointerCast(to, from);
    }
    // any pointer casts to void*
    if (cast(Pointer) from.type && to == new Pointer(new Void))
    {
        return new PointerCast(to, from);
    }
    if (cast(Class) to && cast(Class) from.type)
    {
        auto currentClass = cast(Class) from.type;

        while (currentClass)
        {
            if (currentClass is to)
            {
                return new PointerCast(to, from);
            }
            currentClass = currentClass.superClass;
        }
    }
    assert(false, format!"todo: cast(%s) %s"(to, from.type));
}

class NoopStatement : Statement
{
    override void emit(Generator)
    {
    }
}

// TODO merge with class Function
class Method : Symbol
{
    Class classType;

    string name;

    @NonNull
    Type ret;

    Argument[] args;

    ASTStatement statement;

    string mangle()
    {
        // TODO mangle types
        return format!"_%s_%s"(this.classType.name, this.name);
    }

    void emit(Generator generator, Namespace module_, Class thisType)
    {
        assert(generator.fun is null);
        auto voidp = new Pointer(new Void);
        generator.fun = generator.mod.define(
            mangle,
            ret.emit(generator.mod),
            [voidp.emit(generator.mod)] ~ args.map!(a => a.type.emit(generator.mod)).array
        );
        auto stackframe = new FunctionScope(module_);
        auto argscope = new VarDeclScope(stackframe, Yes.frameBase);
        Statement[] argAssignments;
        argAssignments ~= argscope.declare("this", thisType, new PointerCast(thisType, new ArgExpr(0, voidp)));
        foreach (i, arg; args)
        {
            auto argExpr = new ArgExpr(cast(int) i + 1, arg.type);

            argAssignments ~= argscope.declare(arg.name, arg.type, argExpr);
        }

        auto functionBody = statement.compile(argscope);

        generator.frameReg = generator.fun.alloca(stackframe.structType.emit(generator.mod));
        scope (success)
            generator.resetFrame;

        foreach (statement; argAssignments)
        {
            statement.emit(generator);
        }

        functionBody.emit(generator);
        generator.fun.ret(generator.fun.voidLiteral);
        generator.fun = null;
    }

    Type funcPtrType()
    {
        return new FunctionPointer(ret, args.map!(arg => arg.type).array);
    }

    mixin(GenerateAll);
}

class Class : Type
{
    struct Member
    {
        string name;

        Type type;

        mixin(GenerateThis);
    }

    string name;

    Class superClass;

    Member[] members;

    @(This.Init!null)
    Method[] methods;

    this(string name, Class superClass, Member[] members)
    {
        this.name = name;
        this.superClass = superClass;
        this.members = members;
        this.methods = null;
    }

    override BackendType emit(BackendModule mod)
    {
        return mod.pointerType(mod.structType(this.members.map!(a => a.type.emit(mod)).array));
    }

    size_t structSize() const
    {
        return members.map!(a => a.type.size).sum;
    }

    Struct dataStruct()
    {
        static Member[] allMembers(Class class_)
        {
            if (class_ is null) return null;
            return allMembers(class_.superClass) ~ class_.members;
        }

        auto voidp = new Pointer(new Void);
        return new Struct(
            null,
            [Struct.Member("__classinfo", voidp)] ~ allMembers(this).map!(a => Struct.Member(a.name, a.type)).array,
        );
    }

    Tuple!(string, "name", size_t, "index")[] visibleMembers()
    {
        Tuple!(string, "name", size_t, "index")[] result = superClass ? superClass.visibleMembers : null;
        const ownMembersOffset = superClass ? superClass.dataStruct.members.length : 1;

        foreach (i, member; members)
        {
            result = result.remove!(a => a.name == member.name);
            result ~= tuple!("name", "index")(member.name, ownMembersOffset + i);
        }
        return result;
    }

    Struct classInfoStruct()
    {
        return new Struct(
            null,
            vtable.map!(a => Struct.Member(a.name, a.funcPtrType)).array,
        );
    }

    Method[] vtable()
    {
        auto combinedMethods = superClass ? superClass.vtable : null;

        foreach (method; methods)
        {
            // TODO match types
            alias pred = a => a.name == method.name;

            if (combinedMethods.any!pred)
            {
                combinedMethods[combinedMethods.countUntil!pred] = method;
            }
            else
            {
                combinedMethods ~= method;
            }
        }
        return combinedMethods;
    }

    override size_t size() const
    {
        return size_t.sizeof;
    }

    override string toString() const
    {
        return format!"classref(%s)"(this.name);
    }
}

class ASTClassDecl : ASTType
{
    struct Member
    {
        string name;

        ASTType type;

        mixin(GenerateThis);
    }

    struct Method
    {
        string name;

        ASTType ret;

        ASTArgument[] args;

        ASTStatement body_;

        mixin(GenerateThis);
    }

    string name;

    string superClass;

    Member[] members;

    Method[] methods;

    override Class compile(Namespace namespace)
    {
        Class superClass = null;
        if (this.superClass)
        {
            auto superClassObj = namespace.lookup(this.superClass);
            assert(superClassObj);
            superClass = cast(Class) superClassObj;
            assert(superClass);
        }
        // TODO subscope
        auto class_ = new Class(
            name,
            superClass,
            members.map!(a => Class.Member(a.name, a.type.compile(namespace))).array
        );
        class_.methods = methods.map!(a => new .Method(
            class_,
            a.name,
            a.ret.compile(namespace),
            a.args.map!(b => Argument(b.name, b.type.compile(namespace))).array,
            a.body_)).array;
        return class_;
    }

    mixin(GenerateThis);
}

ASTArgument[] parseArglist(ref Parser parser)
{
    with (parser)
    {
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
            if (!argtype) fail("argument type expected");
            auto argname = parser.parseIdentifier;
            if (!argname) fail("argument name expected");
            args ~= ASTArgument(argname, argtype);
        }
        return args;
    }
}

ASTClassDecl parseClassDecl(ref Parser parser)
{
    with (parser)
    {
        if (!parser.acceptIdentifier("class"))
        {
            return null;
        }
        string name = parser.parseIdentifier;
        string superClass = null;
        if (accept(":")) {
            superClass = parser.parseIdentifier;
            assert(superClass);
        }
        ASTClassDecl.Member[] members;
        ASTClassDecl.Method[] methods;
        expect("{");
        while (!accept("}"))
        {
            ASTType retType;
            string memberName;
            if (accept("this"))
            {
                retType = new ASTVoid;
                memberName = "this";
            }
            else
            {
                retType = parser.parseType;
                if (!retType) parser.fail("expected member type");
                memberName = parser.parseIdentifier;
                if (!memberName) parser.fail("expected member name");
            }
            if (accept("(")) // method
            {
                ASTArgument[] args = parser.parseArglist;
                ASTStatement stmt = parser.parseStatement;
                methods ~= ASTClassDecl.Method(memberName, retType, args, stmt);
            }
            else
            {
                expect(";");
                members ~= ASTClassDecl.Member(memberName, retType);
            }
        }
        return new ASTClassDecl(name, superClass, members, methods);
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

class ASTImport
{
    string name;

    mixin(GenerateThis);
}

ASTImport parseImport(ref Parser parser)
{
    if (!parser.accept("import"))
        return null;
    auto modname = parser.parseIdentifier(".");
    parser.expect(";");
    return new ASTImport(modname);
}

class Module : Namespace
{
    string name;

    struct Entry
    {
        string name;

        Symbol value;
    }

    @(This.Init!null)
    Module[] imports;

    @(This.Init!null)
    Entry[] entries;

    void add(string name, Symbol symbol)
    {
        this.entries ~= Entry(name, symbol);
    }

    void addImport(Module module_)
    {
        imports ~= module_;
    }

    void emit(Generator generator)
    in (generator.fun is null)
    {
        foreach (entry; entries)
        {
            if (auto fun = cast(Function) entry.value)
                if (!fun.declaration)
                    fun.emit(generator, this);
            if (auto class_ = cast(Class) entry.value)
            {
                foreach (method; class_.methods)
                {
                    method.emit(generator, this, class_);
                }
            }
        }
        // TODO each only once!
        foreach (import_; imports) import_.emit(generator);
    }

    Symbol lookupPublic(string name)
    {
        // not counting imports (non-transitive)
        foreach (entry; this.entries)
        {
            if (entry.name == name)
                return entry.value;
        }
        return null;
    }

    override Symbol lookup(string name)
    {
        if (auto entry = lookupPublic(name))
            return entry;
        foreach (import_; this.imports)
        {
            // TODO error on multiple matches
            if (auto entry = import_.lookupPublic(name))
                return entry;
        }
        if (this.parent)
            return this.parent.lookup(name);
        return null;
    }

    mixin(GenerateThis);
}

string moduleToFile(string module_)
{
    return module_.replace(".", "/") ~ ".cx";
}

Module parseModule(string filename)
{
    import std.file : readText;

    string code = readText(filename);
    auto parser = new Parser(code);
    auto module_ = new Module(null, filename);

    parser.expect("module");
    auto modname = parser.parseIdentifier(".");
    parser.expect(";");

    while (!parser.eof)
    {
        if (auto import_ = parser.parseImport)
        {
            auto importedModule = parseModule(import_.name.moduleToFile);

            module_.addImport(importedModule);
        }
        if (auto classDecl = parser.parseClassDecl)
        {
            module_.add(classDecl.name, classDecl.compile(module_));
            continue;
        }
        if (auto strct = parser.parseStructDecl)
        {
            module_.add(strct.name, strct.compile(module_));
            continue;
        }
        if (auto fun = parser.parseFunction)
        {
            module_.add(fun.name, fun.compile(module_));
            continue;
        }

        parser.fail("couldn't parse function or struct");
    }
    return module_;
}

void defineRuntime(Backend backend, BackendModule backModule, Module frontModule)
{
    import backend.interpreter : IpBackendModule;

    auto ipModule = cast(IpBackendModule) backModule;

    void defineCallback(R, T...)(string name, R delegate(T) dg)
    {
        ipModule.defineCallback(name, delegate void(void[] ret, void[][] args)
        in (args.length == T.length, format!"%s expected %s parameters but got %s"(name, T.length, args.length))
        {
            T typedArgs;
            static foreach (i, U; T)
            {
                typedArgs[i] = args[i].as!U;
            }
            static if (is(R == void)) dg(typedArgs);
            else ret.as!R = dg(typedArgs);
        });
    }

    auto languageType(T)()
    {
        static if (is(T == int)) return new Integer;
        else static if (is(T == char)) return new Character;
        else static if (is(T == void)) return new Void;
        else static if (is(T == U*, U)) return new Pointer(languageType!U);
        // take care to match up types!
        else static if (is(T == class) || is(T == interface)) return new Pointer(new Void);
        else static assert(false, T.stringof);
    }

    void definePublicCallback(R, T...)(string name, R delegate(T) dg)
    {
        defineCallback(name, dg);
        Argument[] arguments;
        static foreach (i, U; T)
        {
            arguments ~= Argument("", languageType!U);
        }
        frontModule.addFunction(new Function(name, languageType!R, arguments, true, null));
    }

    definePublicCallback("assert", (int test) { assert(test, "Assertion failed!"); });
    defineCallback("ptr_offset", delegate void*(void* ptr, int offset) { return ptr + offset; });
    definePublicCallback("malloc", (int size) {
        import core.stdc.stdlib : malloc;

        return malloc(size);
    });
    definePublicCallback("print", (char* text) {
        writefln!"%s"(text.to!string);
    });

    definePublicCallback("_backend", delegate Backend() => backend);
    definePublicCallback("_backend_createModule", delegate BackendModule(Backend backend) => backend.createModule());
    definePublicCallback("_backendModule_intType", delegate BackendType(BackendModule mod) => mod.intType());
    definePublicCallback(
        "_backendModule_define",
        delegate BackendFunction(BackendModule mod, char* name, BackendType ret, BackendType* args_ptr, int args_len)
        {
            return mod.define(name.to!string, ret, args_ptr[0 .. args_len]);
        }
    );
    definePublicCallback(
        "_backendModule_dump",
        delegate void(BackendModule mod) { writefln!"(nested) module:\n%s"(mod); },
    );
    definePublicCallback(
        "_backendModule_call",
        delegate void(BackendModule mod, char* name, void* ret, void** args_ptr, int args_len)
        {
            // TODO non-int args
            // TODO stop hardcoding interpreter backend
            (cast(IpBackendModule) mod).call(
                name.to!string,
                ret[0 .. 4],
                args_ptr[0 .. args_len].map!(a => a[0 .. 4]).array,
            );
        }
    );
    definePublicCallback(
        "_backendFunction_arg",
        delegate int(BackendFunction fun, int index) => fun.arg(index));
    definePublicCallback(
        "_backendFunction_intLiteral",
        delegate int(BackendFunction fun, int index) => fun.intLiteral(index));
    definePublicCallback(
        "_backendFunction_call",
        delegate int(BackendFunction fun, BackendType ret, char* name, int* args_ptr, int args_len)
            => fun.call(ret, name.to!string, args_ptr[0 .. args_len]));
    definePublicCallback(
        "_backendFunction_ret",
        delegate void(BackendFunction fun, int value) => fun.ret(value));
    definePublicCallback(
        "_backendFunction_testBranch",
        delegate TestBranchRecord(BackendFunction fun, int reg) => fun.testBranch(reg));
    definePublicCallback(
        "_backendFunction_blockIndex",
        delegate int(BackendFunction fun) => fun.blockIndex);

    definePublicCallback(
        "_testBranchRecord_resolveThen",
        delegate void(TestBranchRecord record, int block) => record.resolveThen(block));
    definePublicCallback(
        "_testBranchRecord_resolveElse",
        delegate void(TestBranchRecord record, int block) => record.resolveElse(block));
}

private template as(T) {
    ref T as(Arg)(Arg arg) { return (cast(T[]) arg)[0]; }
}

void addFunction(Module module_, Function function_)
{
    module_.add(function_.name, function_);
}

version (unittest) { }
else
{
    int main(string[] args)
    {
        import backend.interpreter : IpBackend;

        if (args.length != 2)
        {
            import std.stdio : stderr;

            stderr.writefln!"Usage: %s FILE.cx"(args[0]);
            return 1;
        }
        auto toplevel = parseModule(args[1]);

        auto backend = new IpBackend;
        auto module_ = backend.createModule;

        defineRuntime(backend, module_, toplevel);

        auto output = new Generator(module_);

        toplevel.emit(output);

        writefln!"module:\n%s"(module_);

        module_.call("main", null, null);
        return 0;
    }
}
