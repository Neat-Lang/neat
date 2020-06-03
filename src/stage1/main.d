module main;

import array : Array, ArrayLength, ArrayPointer, ASTArrayLiteral, ASTArraySlice;
import backend.backend;
import backend.platform;
import backend.types;
import base;
import boilerplate;
import parser;
import std.algorithm;
import std.conv : to;
import std.range;
import std.string;
import std.stdio;
import std.typecons;
import std.uni;
import struct_;
import types;

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

    Function compile(Context context)
    {
        return new Function(
            this.name,
            this.ret.compile(context),
            this.args.map!(a => Argument(a.name, a.type.compile(context))).array,
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

    void emit(Generator generator, Context module_)
    {
        assert(generator.fun is null);
        generator.fun = generator.mod.define(
            name,
            ret.emit(module_.platform),
            args.map!(a => a.type.emit(module_.platform)).array
        );
        auto stackframe = new FunctionScope(module_.namespace);
        auto argscope = new VarDeclScope(stackframe, Yes.frameBase);
        Statement[] argAssignments;
        foreach (i, arg; args)
        {
            auto argExpr = new ArgExpr(cast(int) i, arg.type);

            argAssignments ~= argscope.declare(arg.name, arg.type, argExpr);
        }

        auto functionBody = statement.compile(module_.withNamespace(argscope));

        generator.frameReg = generator.fun.alloca(stackframe.structType.emit(module_.platform));
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

class ASTScopeStatement : ASTStatement
{
    @AllNonNull
    ASTStatement[] statements;

    override Statement compile(Context context)
    {
        auto subscope = new VarDeclScope(context.namespace, No.frameBase);

        return new SequenceStatement(
                statements.map!(a => a.compile(Context(context.platform, subscope))).array
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

    override ReturnStatement compile(Context context)
    {
        return new ReturnStatement(value.compile(context).beExpression);
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

class ASTVoidExpression : ASTSymbol
{
    override Expression compile(Context) { return new VoidExpression; }
}

class VoidExpression : Expression
{
    override Type type() { return new Void; }
    override Reg emit(Generator generator)
    {
        return generator.fun.voidLiteral;
    }
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
        ASTSymbol expr;
        if (accept(";")) // return;
        {
            expr = new ASTVoidExpression;
        }
        else
        {
            expr = parser.parseExpression;
            expect(";");
        }
        commit;
        return new ASTReturnStatement(expr);
    }
}

class ASTIfStatement : ASTStatement
{
    ASTSymbol test;

    ASTStatement then;

    ASTStatement else_;

    override IfStatement compile(Context context)
    {
        auto ifscope = new VarDeclScope(context.namespace, No.frameBase);
        auto test = this.test.compile(context.withNamespace(ifscope));
        auto then = this.then.compile(context.withNamespace(ifscope));
        Statement else_;
        if (this.else_) {
            auto elsescope = new VarDeclScope(context.namespace, No.frameBase);
            else_ = this.else_.compile(context.withNamespace(elsescope));
        }

        return new IfStatement(test.beExpression, then, else_);
    }

    mixin(GenerateAll);
}

class IfStatement : Statement
{
    Expression test;

    Statement then;

    @(This.Default!null)
    Statement else_;

    override void emit(Generator output)
    {
        Reg reg = test.emit(output);

        auto tbrRecord = output.fun.testBranch(reg);

        tbrRecord.resolveThen(output.fun.blockIndex);
        then.emit(output);
        auto brRecord = output.fun.branch;
        tbrRecord.resolveElse(output.fun.blockIndex);

        if (this.else_)
        {
            else_.emit(output);
            auto elseBrRecord = output.fun.branch;

            elseBrRecord.resolve(output.fun.blockIndex);
        }
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
        ASTStatement elseStatement;
        if (parser.accept("else"))
        {
            elseStatement = parser.parseStatement;
        }
        commit;
        return new ASTIfStatement(expr, thenStmt, elseStatement);
    }
}

class ASTAssignStatement : ASTStatement
{
    ASTSymbol target;

    ASTSymbol value;

    override AssignStatement compile(Context context)
    {
        auto target = this.target.compile(context);
        auto value = this.value.compile(context);
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

        output.fun.store(valueType.emit(output.platform), target_reg, value_reg);
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

    override Statement compile(Context context)
    {
        if (this.initial)
        {
            auto initial = this.initial.compile(context);

            return context.namespace.find!VarDeclScope.declare(this.name, this.type.compile(context), initial.beExpression);
        }
        else
        {
            return context.namespace.find!VarDeclScope.declare(this.name, this.type.compile(context));
        }
    }

    mixin(GenerateAll);
}

ASTArrayLiteral parseArrayLiteral(ref Parser parser)
{
    with (parser)
    {
        if (!accept("["))
            return null;
        ASTArrayLiteral.Entry[] fields;
        while (!accept("]"))
        {
            if (fields.length) expect(",");
            bool spread = accept("...");
            auto expr = parser.parseExpression;
            assert(expr, "expression expected.");
            fields ~= ASTArrayLiteral.Entry(expr, spread);
        }
        return new ASTArrayLiteral(fields);
    }
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

    override Statement compile(Context context)
    {
        return new ExprStatement(this.value.compile(context).beExpression);
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
    if (auto stmt = parser.parseVarDecl)
        return stmt;
    if (auto stmt = parser.parseAssignStatement)
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

enum BinaryOpType
{
    add,
    sub,
    mul,
    eq,
    gt,
    lt,
    ge,
    le,
    boolAnd,
    boolOr,
}

class ASTBinaryOp : ASTSymbol
{
    BinaryOpType op;

    ASTSymbol left;

    ASTSymbol right;

    override Expression compile(Context context)
    {
        auto left = this.left.compile(context).beExpression;
        auto right = this.right.compile(context).beExpression;
        if (op == BinaryOpType.boolAnd)
            return new BoolAnd(left, right);
        if (op == BinaryOpType.boolOr)
            return new BoolOr(left, right);
        return new BinaryOp(op, left, right);
    }

    mixin(GenerateAll);
}

class BoolOr : Expression
{
    Expression left;

    Expression right;

    override Type type() { return new Integer; }

    override Reg emit(Generator output)
    {
        /**
         * result = left;
         * if (left) goto past;
         * result = right;
         * past:
         */
        Reg result = output.fun.alloca(new BackendIntType);

        Reg leftValue = this.left.emit(output);
        output.fun.store(new BackendIntType, result, leftValue);

        auto condBranch = output.fun.testBranch(leftValue); // if (left)
        condBranch.resolveElse(output.fun.blockIndex);

        Reg rightValue = this.right.emit(output);
        output.fun.store(new BackendIntType, result, rightValue);

        auto exitBranch = output.fun.branch;
        condBranch.resolveThen(output.fun.blockIndex);
        exitBranch.resolve(output.fun.blockIndex);

        return output.fun.load(new BackendIntType, result);
    }

    mixin(GenerateThis);
}

class BoolAnd : Expression
{
    Expression left;

    Expression right;

    override Type type() { return new Integer; }

    override Reg emit(Generator output)
    {
        /**
         * result = left;
         * if (left) result = right;
         */
        Reg result = output.fun.alloca(new BackendIntType);

        Reg leftValue = this.left.emit(output);
        output.fun.store(new BackendIntType, result, leftValue);

        auto condBranch = output.fun.testBranch(leftValue); // if (left)
        condBranch.resolveThen(output.fun.blockIndex);

        Reg rightValue = this.right.emit(output);
        output.fun.store(new BackendIntType, result, rightValue);

        auto exitBranch = output.fun.branch;
        condBranch.resolveElse(output.fun.blockIndex);
        exitBranch.resolve(output.fun.blockIndex);

        return output.fun.load(new BackendIntType, result);
    }

    mixin(GenerateThis);
}

class BinaryOp : Expression
{
    BinaryOpType op;

    Expression left;

    Expression right;

    override Type type()
    {
        return new Integer;
    }

    override Reg emit(Generator output)
    {
        if (op == BinaryOpType.eq)
        {
            auto leftArray = cast(Array) this.left.type;
            auto rightArray = cast(Array) this.right.type;
            if (leftArray && rightArray)
            {
                // TODO temp expr once array properties work on nonreferences
                assert(leftArray == rightArray);
                auto leftLen = (new ArrayLength(this.left)).emit(output);
                auto rightLen = (new ArrayLength(this.right)).emit(output);
                auto leftPtr = (new ArrayPointer(leftArray.elementType, this.left)).emit(output);
                auto rightPtr = (new ArrayPointer(rightArray.elementType, this.right)).emit(output);
                const leftSize = output.platform.size(leftArray.elementType.emit(output.platform));
                return output.fun.call(new BackendIntType, "_arraycmp", [
                    leftPtr, rightPtr, leftLen, rightLen,
                    output.fun.intLiteral(leftSize)]);
            }
        }
        assert(this.left.type == new Integer, format!"expected integer, not %s"(this.left.type));
        assert(this.right.type == new Integer, format!"expected integer, not %s"(this.right.type));
        Reg leftreg = this.left.emit(output);
        Reg rightreg = this.right.emit(output);
        string name = {
            with (BinaryOpType) final switch (this.op)
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
                case boolAnd:
                case boolOr:
                    assert(false, "should be handled separately");
            }
        }();
        return output.fun.call(new BackendIntType, name, [leftreg, rightreg]);
    }

    mixin(GenerateThis);
    mixin(GenerateToString);
}

ASTSymbol parseArithmetic(ref Parser parser, size_t level = 0)
{
    auto left = parser.parseExpressionLeaf;

    if (level <= 4)
    {
        parseMul(parser, left, 4);
    }
    if (level <= 3)
    {
        parseAddSub(parser, left, 3);
    }
    if (level <= 2)
    {
        parseComparison(parser, left, 2);
    }
    if (level <= 1)
    {
        parseBoolAnd(parser, left, 1);
    }
    if (level <= 0)
    {
        parseBoolOr(parser, left, 0);
    }
    return left;
}

void parseMul(ref Parser parser, ref ASTSymbol left, int myLevel)
{
    while (true)
    {
        if (parser.accept("*"))
        {
            auto right = parser.parseArithmetic(myLevel + 1);
            left = new ASTBinaryOp(BinaryOpType.mul, left, right);
            continue;
        }
        break;
    }
}

void parseBoolAnd(ref Parser parser, ref ASTSymbol left, int myLevel)
{
    while (true)
    {
        if (parser.accept("&&"))
        {
            auto right = parser.parseArithmetic(myLevel + 1);
            left = new ASTBinaryOp(BinaryOpType.boolAnd, left, right);
            continue;
        }
        break;
    }
}

void parseBoolOr(ref Parser parser, ref ASTSymbol left, int myLevel)
{
    while (true)
    {
        if (parser.accept("||"))
        {
            auto right = parser.parseArithmetic(myLevel + 1);
            left = new ASTBinaryOp(BinaryOpType.boolOr, left, right);
            continue;
        }
        break;
    }
}

void parseAddSub(ref Parser parser, ref ASTSymbol left, int myLevel)
{
    while (true)
    {
        if (parser.accept("+"))
        {
            auto right = parser.parseArithmetic(myLevel + 1);
            left = new ASTBinaryOp(BinaryOpType.add, left, right);
            continue;
        }
        if (parser.accept("-"))
        {
            auto right = parser.parseArithmetic(myLevel + 1);
            left = new ASTBinaryOp(BinaryOpType.sub, left, right);
            continue;
        }
        break;
    }
}

void parseComparison(ref Parser parser, ref ASTSymbol left, int myLevel)
{
    if (parser.accept("=="))
    {
        auto right = parser.parseArithmetic(myLevel + 1);
        left = new ASTBinaryOp(BinaryOpType.eq, left, right);
    }
    if (parser.accept("!=")) // same as !(a == b)
    {
        auto right = parser.parseArithmetic(myLevel + 1);
        left = new ASTNegation(new ASTBinaryOp(BinaryOpType.eq, left, right));
    }
    if (parser.accept(">="))
    {
        auto right = parser.parseArithmetic(myLevel + 1);
        left = new ASTBinaryOp(BinaryOpType.ge, left, right);
    }
    if (parser.accept(">"))
    {
        auto right = parser.parseArithmetic(myLevel + 1);
        left = new ASTBinaryOp(BinaryOpType.gt, left, right);
    }
    if (parser.accept("<="))
    {
        auto right = parser.parseArithmetic(myLevel + 1);
        left = new ASTBinaryOp(BinaryOpType.le, left, right);
    }
    if (parser.accept("<"))
    {
        auto right = parser.parseArithmetic(myLevel + 1);
        left = new ASTBinaryOp(BinaryOpType.lt, left, right);
    }
}

class ASTWhile : ASTStatement
{
    ASTSymbol cond;

    ASTStatement body_;

    override WhileLoop compile(Context context)
    {
        auto subscope = new VarDeclScope(context.namespace, No.frameBase);
        auto condExpr = this.cond.compile(context.withNamespace(subscope));
        auto bodyStmt = this.body_.compile(context.withNamespace(subscope));

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

    Statement compile(Context context)
    {
        /*
         * hack until break/continue:
         * for (decl; test; step) body
         * decl; while (test) { body; step; }
         */
        auto forscope = context.withNamespace(new VarDeclScope(context.namespace, No.frameBase));
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

    override Expression compile(Context context)
    {
        auto target = this.target.compile(context);
        auto args = this.args.map!(a => a.compile(context).beExpression).array;

        return target.call(args);
    }

    mixin(GenerateAll);
}

class Call : Expression
{
    Function function_;

    Expression[] args;

    this(Function function_, Expression[] args)
    {
        assert(function_.args.length == args.length, format!"'%s' expected %s args, not %s"(
            function_.name, function_.args.length, args.length));
        foreach (i, ref arg; args)
        {
            import std.stdio : stderr;

            scope(failure)
                stderr.writefln!"While converting arg %s of %s to %s:"(
                    i, function_.name, function_.args[i].type);
            arg = arg.implicitConvertTo(function_.args[i].type);
        }
        this.function_ = function_;
        this.args = args.dup;
    }

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
        return output.fun.call(type.emit(output.platform), function_.name, regs);
    }

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
            type.emit(output.platform), funcPtr.emit(output), regs);
    }

    mixin(GenerateThis);
    mixin(GenerateToString);
}

class Variable : ASTSymbol
{
    string name;

    override Symbol compile(Context context)
    out (result; result !is null)
    {
        auto ret = context.namespace.lookup(name);
        assert(ret, format!"%s not found"(name));
        return ret;
    }

    mixin(GenerateThis);
    mixin(GenerateToString);
}

class ASTLiteral : ASTSymbol
{
    int value;

    override Literal compile(Context)
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

class ASTDereference : ASTSymbol
{
    ASTSymbol base;

    override Dereference compile(Context context)
    {
        return new Dereference(base.compile(context).beExpression);
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

        return output.fun.load(this.type().emit(output.platform), reg);
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

    override Expression compile(Context context)
    {
        // &function
        if (auto var = cast(Variable) base)
        {
            auto target = context.namespace.lookup(var.name);

            if (auto fun = cast(Function) target)
            {
                return new FunctionReference(fun);
            }
        }
        auto baseExpression = base.compile(context);
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

    override Symbol compile(Context context)
    {
        import array : Array, ArrayLength;

        auto base = this.base.compile(context);
        auto expr = cast(Expression) base;

        if (expr && cast(Array) expr.type && member == "length")
        {
            return new ArrayLength(expr);
        }

        if (expr && cast(Array) expr.type && member == "ptr")
        {
            return new ArrayPointer((cast(Array) expr.type).elementType, expr);
        }

        return base.accessMember(this.member);
    }

    mixin(GenerateThis);
}

ASTSymbol parseMember(ref Parser parser, ASTSymbol base)
{
    with (parser)
    {
        begin;
        if (accept("..") || !accept(".")) // don't accept '..'
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

    override Expression compile(Context context)
    {
        auto base = this.base.compile(context).beExpression;
        auto index = this.index.compile(context).beExpression;

        if (auto array_ = cast(Array) base.type)
        {
            // TODO bounds check
            base = new ArrayPointer(array_.elementType, base);
        }

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
        int size = context.platform.size((cast(Pointer) base.type).target.emit(context.platform));
        auto offset = new Call(int_mul, [index, new Literal(size)]);

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
        if (accept(".."))
        {
            auto lower = index, upper = parser.parseExpression;
            assert(upper, "slice upper bound expected");
            expect("]");
            return new ASTArraySlice(base, lower, upper);
        }
        expect("]");
        commit;
        return new ASTIndexAccess(base, index);
    }
}

class ASTNewClassExpression : ASTSymbol
{
    ASTType type;

    Nullable!(ASTSymbol[]) args;

    override Expression compile(Context context)
    {
        auto type = this.type.compile(context);
        auto classType = cast(Class) type;
        auto classptr = new NewClassExpression(classType);

        if (args.isNull)
        {
            return classptr;
        }
        Expression[] argExpressions = this.args.get.map!(a => a.compile(context).beExpression).array;
        assert(classType, format!"expected new <class>, not %s"(type));
        return new CallCtorExpression(classptr, argExpressions);
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
        auto voidp = (new Pointer(new Void)).emit(output.platform);
        int classInfoSize = output.platform.size(classInfoStruct.emit(output.platform));
        auto classInfoPtr = output.fun.call(voidp, "malloc", [output.fun.intLiteral(classInfoSize)]);
        foreach (i, method; classType.vtable)
        {
            auto funcPtr = method.funcPtrType;
            auto target = output.fun.fieldOffset(classInfoStruct.emit(output.platform), classInfoPtr, cast(int) i);
            auto src = output.fun.getFuncPtr(method.mangle);
            output.fun.store(funcPtr.emit(output.platform), target, src);
        }
        int classDataSize = output.platform.size(classDataStruct.emit(output.platform));
        auto classPtr = output.fun.call(voidp, "malloc", [output.fun.intLiteral(classDataSize)]);
        auto classInfoTarget = output.fun.fieldOffset(classDataStruct.emit(output.platform), classPtr, 0);
        output.fun.store(voidp, classInfoTarget, classInfoPtr);

        return classPtr;
    }

    mixin(GenerateThis);
}

class ASTNegation : ASTSymbol
{
    ASTSymbol next;

    override Negation compile(Context context)
    {
        return new Negation(
            this.next
                .compile(context)
                .beExpression
                .implicitConvertTo(new Integer));
    }

    mixin(GenerateThis);
}

class Negation : Expression
{
    Expression next;

    override Type type()
    {
        return new Integer;
    }

    override Reg emit(Generator output)
    {
        auto next = this.next.emit(output);
        return output.fun.call(new BackendIntType, "cxruntime_int_negate", [next]);
    }

    mixin(GenerateThis);
}

ASTSymbol parseExpressionLeaf(ref Parser parser)
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
        if (accept("!"))
        {
            auto next = parser.parseExpressionLeaf;

            assert(next !is null);
            return new ASTNegation(next);
        }
        auto currentExpr = parser.parseExpressionBase;
        assert(currentExpr);
        return parser.parseProperties(currentExpr);
    }
}

ASTSymbol parseProperties(ref Parser parser, ASTSymbol current)
{
    while (true)
    {
        if (auto expr = parser.parseInstanceOf(current))
        {
            current = expr;
            continue;
        }
        if (auto expr = parser.parseCall(current))
        {
            current = expr;
            continue;
        }
        if (auto expr = parser.parseMember(current))
        {
            current = expr;
            continue;
        }
        if (auto expr = parser.parseIndex(current))
        {
            current = expr;
            continue;
        }
        break;
    }
    return current;
}

class ASTInstanceOf : ASTSymbol
{
    ASTSymbol base;

    ASTType target;

    override Symbol compile(Context context)
    {
        auto base = this.base.compile(context).beExpression;
        assert(cast(Class) base.type);
        auto target = cast(Class) this.target.compile(context);
        assert(target);
        return base.accessMember("__instanceof").call([new StringLiteral(target.name)]);
    }

    mixin(GenerateThis);
}

ASTSymbol parseInstanceOf(ref Parser parser, ASTSymbol left)
{
    parser.begin;
    if (!(parser.accept(".") && parser.accept("instanceOf")))
    {
        parser.revert;
        return null;
    }
    parser.expect("(");
    auto type = parser.parseType;
    parser.expect(")");
    parser.commit;
    return new ASTInstanceOf(left, type);
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

        return new ASTStringLiteral(str.replaceEscapes);
    }
}

string replaceEscapes(string text)
{
    string result;
    int i;
    while (i < text.length)
    {
        char ch = text[i++];
        if (ch == '\\')
        {
            char ctl = text[i++];
            switch (ctl)
            {
                case 'r':
                    result ~= '\r';
                    break;
                case 'n':
                    result ~= '\n';
                    break;
                case 't':
                    result ~= '\t';
                    break;
                default:
                    assert(false, format!"Unknown control sequence \\%s"(ctl));
            }
        }
        else
        {
            result ~= ch;
        }
    }
    return result;
}

class ASTStringLiteral : ASTSymbol
{
    string text;

    StringLiteral compile(Context)
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
        return new Array(new Character);
    }

    override Reg emit(Generator output)
    {
        auto voidp = new BackendPointerType(new BackendVoidType);
        // TODO allocaless
        auto structType = type.emit(output.platform);
        Reg structReg = output.fun.alloca(structType);
        Reg ptrField = output.fun.fieldOffset(structType, structReg, 0);
        Reg lenField = output.fun.fieldOffset(structType, structReg, 1);

        output.fun.store(voidp, ptrField, output.fun.stringLiteral(this.text));
        output.fun.store(new BackendIntType, lenField, output.fun.intLiteral(cast(int)  this.text.length));
        return output.fun.load(structType, structReg);
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
    if (parser.accept("\""))
    {
        return parser.parseStringLiteral("\"");
    }
    if (parser.accept("("))
    {
        auto result = parser.parseExpression;
        parser.expect(")");
        return result;
    }
    if (auto arrayLiteral = parser.parseArrayLiteral)
    {
        return arrayLiteral;
    }
    parser.fail("Base expression expected.");
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
    // TODO bool
    if (cast(Integer) to && cast(Pointer) from.type)
    {
        auto voidp = new Pointer(new Void);
        auto rt_ptr_test = new Function("cxruntime_ptr_test",
            new Integer,
            [Argument("", voidp)],
            true, null);
        return new Call(rt_ptr_test, [new PointerCast(voidp, from)]);
    }
    assert(false, format!"todo: cast(%s) %s"(to, from.type));
}

class NoopStatement : Statement
{
    override void emit(Generator)
    {
    }
}

class NullExpr : Expression
{
    private Type type_;

    override Type type()
    {
        return this.type_;
    }

    override Reg emit(Generator generator)
    {
        // TODO allocaless
        // exploit that alloca are zero initialized
        auto type = this.type.emit(generator.platform);
        auto reg = generator.fun.alloca(type);

        return generator.fun.load(type, reg);
    }

    mixin(GenerateThis);
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

    @(This.Default!null)
    Statement compiledStatement;

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
            ret.emit(generator.platform),
            [voidp.emit(generator.platform)] ~ args.map!(a => a.type.emit(generator.platform)).array
        );

        if (!compiledStatement)
        {
            Statement[] argAssignments;
            auto stackframe = new FunctionScope(module_);

            auto argscope = new VarDeclScope(stackframe, Yes.frameBase);
            argAssignments ~= argscope.declare("this", thisType, new PointerCast(thisType, new ArgExpr(0, voidp)));
            foreach (i, arg; args)
            {
                auto argExpr = new ArgExpr(cast(int) i + 1, arg.type);

                argAssignments ~= argscope.declare(arg.name, arg.type, argExpr);
            }

            this.compiledStatement = this.statement.compile(Context(generator.platform, argscope));

            generator.frameReg = generator.fun.alloca(stackframe.structType.emit(generator.platform));

            foreach (statement; argAssignments)
            {
                statement.emit(generator);
            }
        }

        scope (success)
        {
            generator.resetFrame;
            generator.fun = null;
        }

        this.compiledStatement.emit(generator);
        generator.fun.ret(generator.fun.voidLiteral);
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

    @(This.Init!null)
    Member[] members;

    @(This.Init!null)
    Method[] methods;

    this(string name, Class superClass)
    {
        this.name = name;
        this.superClass = superClass;
        this.members = null;
        this.methods = null;
    }

    override BackendType emit(Platform platform)
    {
        return new BackendPointerType(new BackendVoidType);
        /**
         * Class A { A a; } wouldn't work
         */
        /*return new BackendPointerType(
            new BackendStructType(this.members.map!(a => a.type.emit(platform)).array));*/
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

    void genInstanceofMethod()
    {
        auto voidp = new Pointer(new Void);
        auto strng = new Array(new Character);

        Statement[] castStmts;
        auto thisptr = new ArgExpr(0, voidp);
        auto target = new ArgExpr(1, strng);
        auto nullptr = new NullExpr(voidp);
        auto current = this;
        while (current)
        {
            auto test = new BinaryOp(BinaryOpType.eq, target, new StringLiteral(current.name));

            castStmts ~= new IfStatement(test, new ReturnStatement(thisptr));
            current = current.superClass;
        }
        castStmts ~= new ReturnStatement(nullptr);

        auto stmt = new SequenceStatement(castStmts);

        methods ~= new Method(this, "__instanceof", voidp, [Argument("target", strng)], null, stmt);
    }

    override string toString() const
    {
        return format!"classref(%s)"(this.name);
    }
}

class ClassScope : Namespace
{
    Class class_;

    override Symbol lookup(string name)
    {
        if (name == this.class_.name)
        {
            return this.class_;
        }
        return parent.lookup(name);
    }

    mixin(GenerateThis);
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

    override Class compile(Context context)
    {
        Class superClass = null;
        if (this.superClass)
        {
            auto superClassObj = context.namespace.lookup(this.superClass);
            assert(superClassObj);
            superClass = cast(Class) superClassObj;
            assert(superClass);
        }
        // FIXME proxy type
        auto class_ = new Class(name, superClass);
        auto classScope = new ClassScope(context.namespace, class_);
        auto classContext = context.withNamespace(classScope);

        class_.members = this.members
            .map!(a => Class.Member(a.name, a.type.compile(classContext)))
            .array;
        class_.methods = methods.map!(a => new .Method(
            class_,
            a.name,
            a.ret.compile(classContext),
            a.args.map!(b => Argument(b.name, b.type.compile(classContext))).array,
            a.body_)).array;
        class_.genInstanceofMethod;
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
                    fun.emit(generator, Context(generator.platform, this));
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

Module parseModule(string filename, string[] includes, Platform platform, Module[] defaultImports)
{
    import std.file : exists, readText;
    import std.path : chainPath;

    string path = filename;
    if (!path.exists)
    {
        foreach (includePath; includes)
        {
            if (includePath.chainPath(filename).exists)
            {
                path = includePath.chainPath(filename).array;
                break;
            }
        }
        assert(path.exists, format!"cannot find file '%s'"(filename));
    }
    string code = readText(path);
    auto parser = new Parser(path, code);

    parser.expect("module");
    auto modname = parser.parseIdentifier(".");
    parser.expect(";");

    assert(filename == modname.moduleToFile);
    auto module_ = new Module(null, modname);
    auto context = Context(platform, module_);

    defaultImports.each!(a => module_.addImport(a));

    while (!parser.eof)
    {
        if (auto import_ = parser.parseImport)
        {
            auto importedModule = parseModule(
                import_.name.moduleToFile, includes, platform, defaultImports);

            module_.addImport(importedModule);
        }
        if (auto classDecl = parser.parseClassDecl)
        {
            module_.add(classDecl.name, classDecl.compile(context));
            continue;
        }
        if (auto strct = parser.parseStructDecl)
        {
            module_.add(strct.name, strct.compile(context));
            continue;
        }
        if (auto fun = parser.parseFunction)
        {
            module_.add(fun.name, fun.compile(context));
            continue;
        }

        parser.fail("couldn't parse function or struct");
    }
    return module_;
}

void defineRuntime(Backend backendObj, BackendModule backModule, Module frontModule)
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
        else static if (is(typeof(cast() T.init) == char)) return new Character;
        else static if (is(T == void)) return new Void;
        else static if (is(T == U*, U)) return new Pointer(languageType!U);
        else static if (is(T == U[], U)) return new Array(languageType!U);
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
    definePublicCallback("realloc", (void* ptr, int size) {
        import core.stdc.stdlib : realloc;

        return realloc(ptr, size);
    });
    defineCallback("memcpy", (void* target, void* source, int size) {
        import core.stdc.string : memcpy;

        return memcpy(target, source, size);
    });
    definePublicCallback("print", (string text) {
        writefln!"%s"(text.ptr[0 .. text.length]);
    });
    definePublicCallback("strlen", (char* text) { return cast(int) text.to!string.length; });
    definePublicCallback("strncmp", (char* text, char* cmp, int limit) { return int(text[0 .. limit] == cmp[0 .. limit]); });
    definePublicCallback("atoi", (char[] text) {
        import std.conv : parse;

        return parse!int(text);
    });

    definePublicCallback("_backend", delegate Backend() => backendObj);
    definePublicCallback("_backend_createModule", delegate BackendModule(Backend backend) => backend.createModule());
    definePublicCallback("_backendModule_intType", delegate BackendType(BackendModule mod) =>
        new BackendIntType);
    definePublicCallback(
        "_backendModule_define",
        delegate BackendFunction(
            BackendModule mod, char[] name, BackendType ret, BackendType* args_ptr, int args_len)
        {
            return mod.define(name.dup, ret, args_ptr[0 .. args_len]);
        }
    );
    defineCallback("_arraycmp", (void* left, void* right, int leftlen, int rightlen, int elemsize)
    {
        if (leftlen != rightlen) return 0;
        auto leftArray = (cast(ubyte*) left)[0 .. leftlen * elemsize];
        auto rightArray = (cast(ubyte*) right)[0 .. rightlen * elemsize];
        return leftArray == rightArray ? 1 : 0;
    });
    definePublicCallback(
        "_backendModule_dump",
        delegate void(BackendModule mod) { writefln!"(nested) module:\n%s"(mod); },
    );
    definePublicCallback(
        "_backendModule_call",
        delegate void(BackendModule mod, void* ret, char[] name, void** args_ptr, int args_len)
        {
            // TODO non-int args
            // TODO stop hardcoding interpreter backend
            (cast(IpBackendModule) mod).call(
                name.dup,
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
        delegate int(BackendFunction fun, BackendType ret, char[] name, int* args_ptr, int args_len)
            => fun.call(ret, name.dup, args_ptr[0 .. args_len]));
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
    static if (is(T == U[], U))
    {
        T as(void[] arg) {
            struct ArrayHack { align(4) U* ptr; int length; }
            auto arrayVal = arg.as!ArrayHack;
            return arrayVal.ptr[0 .. arrayVal.length];
        }
    }
    else
    {
        ref T as(void[] arg) {
            assert(arg.length == T.sizeof, format!"arg has invalid size %s for %s"(arg.length, T.sizeof));
            return (cast(T[]) arg)[0];
        }
    }
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

        string[] includes;
        foreach (arg; args)
        {
            if (arg.startsWith("-I"))
            {
                includes ~= arg[2 .. $];
            }
        }
        args = args.filter!(a => !a.startsWith("-I")).array;

        if (args.length != 2)
        {
            import std.stdio : stderr;

            stderr.writefln!"Usage: %s [-Iincludepath]* FILE.cx"(args[0]);
            return 1;
        }
        auto defaultPlatform = new DefaultPlatform;
        auto builtins = new Module(null, null);
        auto backend = new IpBackend(defaultPlatform);
        auto module_ = backend.createModule;

        defineRuntime(backend, module_, builtins);
        builtins.add("string", new Array(new Character));
        builtins.add("true", new Literal(1));
        builtins.add("false", new Literal(0));

        auto toplevel = parseModule(args[1], includes, defaultPlatform, [builtins]);

        auto output = new Generator(defaultPlatform, module_);

        toplevel.emit(output);

        writefln!"module:\n%s"(module_);

        module_.call("main", null, null);
        return 0;
    }
}
