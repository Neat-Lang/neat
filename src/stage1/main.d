module main;

import array : Array, ArrayExpression, ArrayLength, ArrayPointer, ArraySlice, getArrayLen, getArrayPtr, makeArray;
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

            argAssignments ~= argscope.declare(arg.name, arg.type, argExpr, Loc.init);
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

    Loc loc;

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

        return new IfStatement(test.beExpression.truthy(loc), then, else_);
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

        auto label = output.fun.getLabel;
        output.fun.testBranch(reg, label ~ "_then", label ~ "_else");

        output.fun.setLabel(label ~ "_then");
        then.emit(output);
        output.fun.branch(label ~ "_fin");

        output.fun.setLabel(label ~ "_else");

        if (this.else_)
        {
            else_.emit(output);
            output.fun.branch(label ~ "_fin");
        }
        output.fun.setLabel(label ~ "_fin");
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
        return new ASTIfStatement(expr, thenStmt, elseStatement, loc);
    }
}

class ASTAssignStatement : ASTStatement
{
    ASTSymbol target;

    ASTSymbol value;

    Loc loc;

    override AssignStatement compile(Context context)
    {
        auto target = this.target.compile(context);
        auto value = this.value.compile(context);
        auto targetref = cast(Reference) target;
        this.loc.assert_(targetref, "target of assignment must be a reference");
        return new AssignStatement(targetref, value.beExpression.implicitConvertTo(targetref.type(), loc));
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
    mixin(ParserGuard!());
    with (parser)
    {
        begin;
        auto lhs = parser.parseExpressionLeaf;
        if (!lhs)
        {
            revert;
            return null;
        }
        Nullable!BinaryOpType operator;
        if (accept("=")) { }
        else if (accept("+=")) operator = BinaryOpType.add;
        else if (accept("-=")) operator = BinaryOpType.sub;
        else if (accept("*=")) operator = BinaryOpType.mul;
        else if (accept("~=")) operator = BinaryOpType.cat;
        else {
            revert;
            return null;
        }
        auto expr = parser.parseExpression;
        commit;
        if (!operator.isNull) {
            expr = new ASTBinaryOp(operator.get, lhs, expr, loc);
        }
        return new ASTAssignStatement(lhs, expr, loc);
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

    bool infer;

    ASTType type;

    ASTSymbol initial;

    invariant(infer == !type);
    invariant(!infer || !!initial);

    Loc loc;

    override Statement compile(Context context)
    {
        Type type;
        if (this.type) type = this.type.compile(context);
        if (this.initial)
        {
            auto initial = this.initial.compile(context).beExpression(this.loc);
            if (infer) {
                assert(!type);
                type = initial.type();
            }

            return context.namespace.find!VarDeclScope.declare(this.name, type, initial, this.loc);
        }
        else
        {
            return context.namespace.find!VarDeclScope.declare(this.name, type);
        }
    }

    mixin(GenerateAll);
}

ASTVarDeclStatement parseVarDecl(ref Parser parser)
{
    with (parser)
    {
        begin;
        bool infer = false;
        ASTType type;
        if (parser.acceptIdentifier("auto")) {
            infer = true;
        } else {
            type = parser.parseType;
            if (!type)
            {
                revert;
                return null;
            }
        }
        auto name = parser.parseIdentifier;
        if (!name)
        {
            revert;
            return null;
        }
        ASTSymbol initial = null;
        if (infer) {
            expect("=");
            initial = parser.parseExpression;
            assert(initial);
        }
        else if (accept("="))
        {
            initial = parser.parseExpression;
            assert(initial);
        }
        expect(";");
        commit;
        return new ASTVarDeclStatement(name, infer, type, initial, loc);
    }
}

class ASTExprStatement : ASTStatement
{
    ASTSymbol value;

    Loc loc;

    override Statement compile(Context context)
    {
        return new ExprStatement(this.value.compile(context).beExpression(loc));
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
        return new ASTExprStatement(value, loc);
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
    mixin(ParserGuard!());
    return parser.parseArithmetic;
}

enum BinaryOpType
{
    add,
    sub,
    cat,
    mul,
    eq,
    gt,
    lt,
    ge,
    le,
    boolAnd,
    boolOr,
    bitAnd,
}

class ASTBinaryOp : ASTSymbol
{
    BinaryOpType op;

    ASTSymbol left;

    ASTSymbol right;

    Loc loc;

    override Expression compile(Context context)
    {
        auto left = this.left.compile(context).beExpression(loc);
        auto right = this.right.compile(context).beExpression(loc);
        if (op == BinaryOpType.cat)
            return new ArrayCat(left, right, loc);
        if (op == BinaryOpType.boolAnd)
            return new BoolAnd(left.truthy(loc), right.truthy(loc));
        if (op == BinaryOpType.boolOr)
            return new BoolOr(left.truthy(loc), right.truthy(loc));
        if (op == BinaryOpType.eq && cast(Array) left.type && cast(Array) right.type)
            return new ArrayEqual(left, right);
        return new BinaryOp(op, left, right, loc);
    }

    mixin(GenerateAll);
}

class ArrayCat : Expression
{
    Expression left;

    Expression right;

    Loc loc;

    override Type type() {
        auto leftArray = cast(Array) left.type;
        loc.assert_(leftArray, "array expected");
        auto rightArray = cast(Array) right.type;
        loc.assert_(
            right.type == leftArray.elementType || rightArray && rightArray == leftArray,
            "type mismatch");

        return left.type;
    }

    override Reg emit(Generator output)
    {
        // TODO simplify this?
        auto leftReg = this.left.emit(output);
        auto leftType = cast(Array) this.left.type;
        auto rightType = this.right.type;
        auto leftLen = getArrayLen(output, leftType, leftReg);
        auto leftPtr = getArrayPtr(output, leftType, leftReg);
        auto elementSize = output.fun.wordLiteral(output.platform,
            leftType.elementType.emit(output.platform).size(output.platform));
        if (leftType.elementType == rightType)
        {
            // size = sizeof(T) * (array.length + 1)
            auto oldSize = output.fun.binop("*", output.platform.nativeWordSize, leftLen, elementSize);
            auto newSize = output.fun.binop("+", output.platform.nativeWordSize, oldSize, elementSize);
            auto voidp = (new Pointer(new Void)).emit(output.platform);
            auto newArrayPtr = output.fun.call(voidp, "cxruntime_alloc", [newSize]);
            output.fun.call((new Void).emit(output.platform), "memcpy", [newArrayPtr, leftPtr, oldSize]);
            // *(ptr + prevLength) = right;
            auto newElement = output.fun.call(voidp, "ptr_offset", [newArrayPtr, oldSize]);
            output.fun.store(this.right.type.emit(output.platform), newElement, this.right.emit(output));

            // return ptr[0 .. prevLength + 1];
            auto newArrayLen = output.fun.binop(
                "+", output.platform.nativeWordSize,
                leftLen, output.fun.wordLiteral(output.platform, 1));
            return makeArray(output, leftType, newArrayLen, newArrayPtr);
        }
        if (leftType == rightType)
        {
            auto rightReg = this.right.emit(output);
            auto rightLen = getArrayLen(output, rightType, rightReg);
            auto rightPtr = getArrayPtr(output, rightType, rightReg);
            auto newArrayLen = output.fun.binop("+", output.platform.nativeWordSize, leftLen, rightLen);
            auto leftBytes = output.fun.binop("*", output.platform.nativeWordSize, leftLen, elementSize);
            auto rightBytes = output.fun.binop("*", output.platform.nativeWordSize, rightLen, elementSize);
            // size = sizeof(T) * (left.length + right.length)
            auto newBytes = output.fun.binop("*", output.platform.nativeWordSize, newArrayLen, elementSize);

            auto voidp = (new Pointer(new Void)).emit(output.platform);
            auto newArrayPtr = output.fun.call(voidp, "cxruntime_alloc", [newBytes]);
            // write left at 0
            output.fun.call((new Void).emit(output.platform), "memcpy", [newArrayPtr, leftPtr, leftBytes]);
            // write right at ptr + leftLen
            auto startRightPtr = output.fun.call(voidp, "ptr_offset", [newArrayPtr, leftBytes]);
            output.fun.call((new Void).emit(output.platform), "memcpy", [startRightPtr, rightPtr, rightBytes]);

            return makeArray(output, leftType, newArrayLen, newArrayPtr);
        }
        assert(false);
    }

    mixin(GenerateThis);
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

        auto label = output.fun.getLabel;
        output.fun.testBranch(leftValue, label ~ "_past", label ~ "_right"); // if (left)
        output.fun.setLabel(label ~ "_right");

        Reg rightValue = this.right.emit(output);
        output.fun.store(new BackendIntType, result, rightValue);
        output.fun.branch(label ~ "_past");

        output.fun.setLabel(label ~ "_past");
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

        auto label = output.fun.getLabel;
        output.fun.testBranch(leftValue, label ~ "_true", label ~ "_past"); // if (left)
        output.fun.setLabel(label ~ "_true");

        Reg rightValue = this.right.emit(output);
        output.fun.store(new BackendIntType, result, rightValue);
        output.fun.branch(label ~ "_past");

        output.fun.setLabel(label ~ "_past");
        return output.fun.load(new BackendIntType, result);
    }

    mixin(GenerateThis);
}

class ArrayEqual : Expression
{
    Expression left;

    Expression right;

    override Type type() { return new Integer; }

    override int emit(Generator output)
    {
        auto leftArray = cast(Array) this.left.type;
        auto rightArray = cast(Array) this.right.type;
        assert(leftArray && rightArray);
        assert(leftArray == rightArray);
        auto left = this.left.emit(output);
        auto right = this.right.emit(output);
        auto leftLen = getArrayLen(output, leftArray, left);
        auto rightLen = getArrayLen(output, rightArray, right);
        auto leftPtr = getArrayPtr(output, leftArray, left);
        auto rightPtr = getArrayPtr(output, rightArray, right);
        const leftSize = leftArray.elementType.emit(output.platform).size(output.platform);
        return output.fun.call(new BackendIntType, "_arraycmp", [
            leftPtr, rightPtr, leftLen, rightLen,
            output.fun.wordLiteral(output.platform, leftSize)]);
    }

    mixin(GenerateThis);
}

class IntToLong : Expression
{
    Expression intValue;

    override Type type() { return new Long; }

    override Reg emit(Generator output) {
        assert(cast(Integer) this.intValue.type);
        Reg intValue = this.intValue.emit(output);

        return output.fun.signExtend(intValue, 4, 8);
    }

    mixin(GenerateThis);
}

class BinaryOp : Expression
{
    BinaryOpType op;

    Expression left;

    Expression right;

    Loc loc;

    override Type type()
    {
        with (BinaryOpType) final switch (this.op) {
            case add:
            case sub:
            case mul:
            case bitAnd:
                // arithmetic
                auto rightType = this.right.type;
                if (cast(Long) rightType) return rightType;
                return this.left.type;
            case eq:
            case gt:
            case lt:
            case ge:
            case le:
                return new Integer; // comparison
            case cat:
            case boolAnd:
            case boolOr:
                assert(false);
        }
    }

    override Reg emit(Generator output)
    {
        auto left = this.left;
        auto right = this.right;
        if (cast(Integer) left.type && cast(Long) right.type) {
            left = new IntToLong(left);
        }
        if (cast(Long) left.type && cast(Integer) right.type) {
            right = new IntToLong(right);
        }
        loc.assert_(cast(Integer) left.type || cast(Long) left.type, format!"expected integer/long, not %s"(left.type));
        loc.assert_(left.type == right.type, format!"types don't match: %s, %s"(left.type, right.type));
        int size = (cast(Integer) left.type) ? 4 : 8;
        Reg leftreg = left.emit(output);
        Reg rightreg = right.emit(output);
        string op = {
            with (BinaryOpType) final switch (this.op)
            {
                case add:
                    return "+";
                case sub:
                    return "-";
                case mul:
                    return "*";
                case bitAnd:
                    return "&";
                case eq:
                    return "==";
                case gt:
                    return ">";
                case lt:
                    return "<";
                case ge:
                    return ">=";
                case le:
                    return "<=";
                case cat:
                case boolAnd:
                case boolOr:
                    assert(false, "should be handled separately");
            }
        }();
        return output.fun.binop(op, size, leftreg, rightreg);
    }

    mixin(GenerateThis);
    mixin(GenerateToString);
}

ASTSymbol parseArithmetic(ref Parser parser, size_t level = 0)
{
    auto left = parser.parseExpressionLeaf;

    if (level <= 5) parseBitAnd(parser, left, 5);
    if (level <= 4) parseMul(parser, left, 4);
    if (level <= 3) parseAddSubCat(parser, left, 3);
    if (level <= 2) parseComparison(parser, left, 2);
    if (level <= 1) parseBoolAnd(parser, left, 1);
    if (level <= 0) parseBoolOr(parser, left, 0);
    return left;
}

void parseMul(ref Parser parser, ref ASTSymbol left, int myLevel)
{
    while (true)
    {
        if (parser.accept("*"))
        {
            auto right = parser.parseArithmetic(myLevel + 1);
            left = new ASTBinaryOp(BinaryOpType.mul, left, right, parser.loc);
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
            left = new ASTBinaryOp(BinaryOpType.boolAnd, left, right, parser.loc);
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
            left = new ASTBinaryOp(BinaryOpType.boolOr, left, right, parser.loc);
            continue;
        }
        break;
    }
}

void parseBitAnd(ref Parser parser, ref ASTSymbol left, int myLevel)
{
    while (true)
    {
        parser.begin;
        if (parser.accept("&") && !parser.accept("&"))
        {
            parser.commit;
            auto right = parser.parseArithmetic(myLevel + 1);
            left = new ASTBinaryOp(BinaryOpType.bitAnd, left, right, parser.loc);
            continue;
        }
        parser.revert;
        break;
    }
}

void parseAddSubCat(ref Parser parser, ref ASTSymbol left, int myLevel)
{
    while (true)
    {
        if (parser.accept("+"))
        {
            auto right = parser.parseArithmetic(myLevel + 1);
            left = new ASTBinaryOp(BinaryOpType.add, left, right, parser.loc);
            continue;
        }
        if (parser.accept("-"))
        {
            auto right = parser.parseArithmetic(myLevel + 1);
            left = new ASTBinaryOp(BinaryOpType.sub, left, right, parser.loc);
            continue;
        }
        if (parser.accept("~"))
        {
            auto right = parser.parseArithmetic(myLevel + 1);
            left = new ASTBinaryOp(BinaryOpType.cat, left, right, parser.loc);
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
        left = new ASTBinaryOp(BinaryOpType.eq, left, right, parser.loc);
    }
    if (parser.accept("!=")) // same as !(a == b)
    {
        auto right = parser.parseArithmetic(myLevel + 1);
        left = new ASTNegation(new ASTBinaryOp(BinaryOpType.eq, left, right, parser.loc), parser.loc);
    }
    if (parser.accept(">="))
    {
        auto right = parser.parseArithmetic(myLevel + 1);
        left = new ASTBinaryOp(BinaryOpType.ge, left, right, parser.loc);
    }
    if (parser.accept(">"))
    {
        auto right = parser.parseArithmetic(myLevel + 1);
        left = new ASTBinaryOp(BinaryOpType.gt, left, right, parser.loc);
    }
    if (parser.accept("<="))
    {
        auto right = parser.parseArithmetic(myLevel + 1);
        left = new ASTBinaryOp(BinaryOpType.le, left, right, parser.loc);
    }
    if (parser.accept("<"))
    {
        auto right = parser.parseArithmetic(myLevel + 1);
        left = new ASTBinaryOp(BinaryOpType.lt, left, right, parser.loc);
    }
}

class ASTWhile : ASTStatement
{
    ASTSymbol cond;

    ASTStatement body_;

    Loc loc;

    override WhileLoop compile(Context context)
    {
        auto subscope = new VarDeclScope(context.namespace, No.frameBase);
        auto condExpr = this.cond.compile(context.withNamespace(subscope));
        auto bodyStmt = this.body_.compile(context.withNamespace(subscope));

        return new WhileLoop(condExpr.beExpression.truthy(this.loc), bodyStmt);
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
        auto label = output.fun.getLabel;
        output.fun.branch(label ~ "_start");

        output.fun.setLabel(label ~ "_start"); // start:
        auto condReg = cond.emit(output);
        output.fun.testBranch(condReg, label ~ "_body", label ~ "_end");

        output.fun.setLabel(label ~ "_body");
        body_.emit(output);
        output.fun.branch(label ~ "_start");
        output.fun.setLabel(label ~ "_end");
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

        return new ASTWhile(cond, body_, loc);
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

Expression call(Symbol target, Expression[] args, Loc loc)
{
    if (auto function_ = cast(Function) target)
    {
        return new Call(function_, args, loc);
    }
    if (auto method = cast(ClassMethod) target)
    {
        return new FuncPtrCall(method.funcPtr, [method.thisPtr] ~ args, loc);
    }
    auto expr = cast(Expression) target;
    if (expr && cast(FunctionPointer) expr.type)
    {
        return new FuncPtrCall(expr, args, loc);
    }
    assert(false, format!"unknown call target %s (%s?)"(target, expr ? expr.type : null));
}

class ASTCall : ASTSymbol
{
    ASTSymbol target;

    ASTSymbol[] args;

    Loc loc;

    override Expression compile(Context context)
    {
        auto target = this.target.compile(context);
        auto args = this.args.map!(a => a.compile(context).beExpression(loc)).array;

        return target.call(args, loc);
    }

    mixin(GenerateAll);
}

class Call : Expression
{
    Function function_;

    Expression[] args;

    Loc loc;

    this(Function function_, Expression[] args, Loc loc)
    {
        loc.assert_(function_.args.length == args.length, format!"'%s' expected %s args, not %s"(
            function_.name, function_.args.length, args.length));
        foreach (i, ref arg; args)
        {
            import std.stdio : stderr;

            scope(failure)
                stderr.writefln!"While converting arg %s of %s to %s:"(
                    i, function_.name, function_.args[i].type);
            arg = arg.implicitConvertTo(function_.args[i].type, loc);
        }
        this.function_ = function_;
        this.args = args.dup;
        this.loc = loc;
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

    Loc loc;

    override Type type()
    {
        return (cast(FunctionPointer) funcPtr.type).ret;
    }

    override Reg emit(Generator output)
    {
        auto type = cast(FunctionPointer) funcPtr.type;
        loc.assert_(type.args.length == args.length, format!"expected %s args, not %s"(
            type.args.length, args.length));

        Reg[] regs;
        foreach (i, arg; this.args)
        {
            arg = arg.implicitConvertTo(type.args[i], loc);
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
    Loc loc;

    string name;

    override Symbol compile(Context context)
    out (result; result !is null)
    {
        auto ret = context.namespace.lookup(name);
        loc.assert_(ret, format!"%s not found"(name));
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
    mixin(ParserGuard!());
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
    mixin(ParserGuard!());
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
        return new ASTCall(base, args, loc);
    }
}

class ClassMethod : Symbol
{
    Expression funcPtr;

    Expression thisPtr;

    mixin(GenerateThis);
}

Symbol accessMember(Symbol base, string member, Loc loc)
{
    if (cast(Expression) base)
    {
        auto baseExpr = base.beExpression;

        while (cast(Pointer) baseExpr.type) {
            baseExpr = new Dereference(baseExpr);
        }
        if (auto structType = cast(Struct) baseExpr.type)
        {
            loc.assert_(cast(Reference) baseExpr, "TODO struct member of value");
            auto memberOffset = structType.members.countUntil!(a => a.name == member);
            loc.assert_(memberOffset != -1, "no such member " ~ member);
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
            loc.assert_(!memberOffset.empty, format!"no such member %s in %s"(member, classType));
            return new StructMember(
                new Dereference(asStructPtr),
                cast(int) memberOffset.front.index,
            );
        }

        loc.assert_(false, format!"expected struct/class type for member, not %s of %s"(baseExpr, baseExpr.type));
    }
    loc.assert_(false, format!"expected expression for member access, not %s"(base));
    assert(false);
}

class ASTMember : ASTSymbol
{
    ASTSymbol base;

    string member;

    Loc loc;

    override Symbol compile(Context context)
    {
        import array : Array, ArrayLength;

        auto base = this.base.compile(context);
        auto expr = cast(Expression) base;

        if (expr && cast(Array) expr.type && member == "length")
        {
            return new ArrayLength(expr, context.platform.nativeWordType);
        }

        if (expr && cast(Array) expr.type && member == "ptr")
        {
            return new ArrayPointer((cast(Array) expr.type).elementType, expr);
        }

        return base.accessMember(this.member, loc);
    }

    mixin(GenerateThis);
}

ASTSymbol parseMember(ref Parser parser, ASTSymbol base)
{
    mixin(ParserGuard!());
    with (parser)
    {
        begin;
        if (accept("..") || !accept(".")) // don't accept '..'
        {
            revert;
            return null;
        }
        auto name = parser.parseIdentifier;
        loc.assert_(name, "member expected");
        commit;
        return new ASTMember(base, name, loc);
    }
}

class ASTIndexAccess : ASTSymbol
{
    ASTSymbol base;

    ASTSymbol index;

    Loc loc;

    override Expression compile(Context context)
    {
        auto wordType = context.platform.nativeWordType;
        auto base = this.base.compile(context).beExpression;
        auto index = this.index
            .compile(context)
            .beExpression
            .implicitConvertTo(wordType, loc);

        if (auto array_ = cast(Array) base.type)
        {
            // TODO bounds check
            base = new ArrayPointer(array_.elementType, base);
        }

        assert(cast(Pointer) base.type, "expected pointer for index base");

        auto ptr_offset = new Function("ptr_offset",
            new Pointer(new Void),
            [Argument("", new Pointer(new Void)), Argument("", wordType)],
            true, null);
        int size = (cast(Pointer) base.type).target.emit(context.platform).size(context.platform);
        auto offset = new BinaryOp(BinaryOpType.mul, index, new Literal(size), loc);
        assert(offset.type == wordType);

        return new Dereference(new PointerCast(base.type, new Call(ptr_offset, [base, offset], loc)));
    }

    mixin(GenerateThis);
}

class ASTArraySlice : ASTSymbol
{
    ASTSymbol array;

    ASTSymbol lower;

    ASTSymbol upper;

    Loc loc;

    override ArraySlice compile(Context context)
    {
        auto wordType = context.platform.nativeWordType;

        return new ArraySlice(
            this.array.compile(context).beExpression,
            this.lower.compile(context).beExpression.implicitConvertTo(wordType, loc),
            this.upper.compile(context).beExpression.implicitConvertTo(wordType, loc));
    }

    override string toString() const
    {
        return format!"%s[%s .. %s]"(array, lower, upper);
    }

    mixin(GenerateThis);
}

ASTSymbol parseIndex(ref Parser parser, ASTSymbol base)
{
    mixin(ParserGuard!());
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
            commit;
            return new ASTArraySlice(base, lower, upper, loc);
        }
        expect("]");
        commit;
        return new ASTIndexAccess(base, index, loc);
    }
}

class SizeOf : Expression
{
    Type type_;

    override Type type() { return new Integer; }

    override Reg emit(Generator output)
    {
        int size = this.type_.emit(output.platform).size(output.platform);

        return output.fun.intLiteral(size);
    }

    mixin(GenerateThis);
}

class ASTNewExpression : ASTSymbol
{
    ASTType type;

    ASTSymbol[] args;

    Loc loc;

    override Expression compile(Context context)
    {
        auto type = this.type.compile(context);
        if (auto classType = cast(Class) type) {
            auto classptr = new NewClassExpression(classType);

            Expression[] argExpressions = this.args.map!(a => a.compile(context).beExpression(loc)).array;
            loc.assert_(classType, format!"expected new <class>, not %s"(type));
            return new CallCtorExpression(classptr, argExpressions, loc);
        }
        if (auto arrayType = cast(Array) type) {
            assert(args.length == 1);

            auto wordType = context.platform.nativeWordType;
            auto elementSize = new SizeOf(arrayType.elementType);
            // TODO only compute length once
            auto length = args[0].compile(context).beExpression(loc).implicitConvertTo(wordType, loc);
            auto byteLength = new BinaryOp(BinaryOpType.mul, elementSize, length, loc);
            auto alloc = new Function("cxruntime_alloc", new Pointer(new Void), [Argument("", wordType)], true, null);
            auto dataPtr = new PointerCast(new Pointer(arrayType.elementType), call(alloc, [byteLength], loc));
            return new ArrayExpression(dataPtr, length);
        }
        loc.assert_(false, format!"don't know how to allocate %s"(type));
        assert(false);
    }

    mixin(GenerateThis);
}

class CallCtorExpression : Expression
{
    Expression classptr;

    Expression[] args;

    Loc loc;

    override Type type()
    {
        return this.classptr.type;
    }

    override Reg emit(Generator output)
    {
        auto reg = this.classptr.emit(output);
        auto expr = new RegExpr(type, reg);

        expr.accessMember("this", loc).call(this.args, loc).emit(output);
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
        // oh boy!
        auto classDataStruct = this.classType.dataStruct;
        auto voidp = (new Pointer(new Void)).emit(output.platform);
        auto classInfoPtr = output.fun.symbolList(classType.vtableSymbol);
        int classDataSize = classDataStruct.emit(output.platform).size(output.platform);
        auto classPtr = output.fun.call(voidp, "cxruntime_alloc", [output.fun.wordLiteral(output.platform, classDataSize)]);
        auto classInfoTarget = output.fun.fieldOffset(classDataStruct.emit(output.platform), classPtr, 0);
        output.fun.store(voidp, classInfoTarget, classInfoPtr);

        return classPtr;
    }

    mixin(GenerateThis);
}

class ASTNegation : ASTSymbol
{
    ASTSymbol next;

    Loc loc;

    override Expression compile(Context context)
    {
        auto isTrue = this.next
            .compile(context)
            .beExpression
            .truthy(loc);

        return new BinaryOp(BinaryOpType.eq, isTrue, new Literal(0), loc);
    }

    mixin(GenerateThis);
}

Expression truthy(Expression ex, Loc loc) {
    if (cast(Pointer) ex.type || cast(Class) ex.type)
    {
        auto voidp = new Pointer(new Void);
        auto rt_ptr_test = new Function("cxruntime_ptr_test",
            new Integer,
            [Argument("", voidp)],
            true, null);
        return new Call(rt_ptr_test, [new PointerCast(voidp, ex)], loc);
    }
    loc.assert_(cast(Integer) ex.type || cast(Long) ex.type, "integer expected");
    // (a == 0) == 0
    return new BinaryOp(
        BinaryOpType.eq,
        new BinaryOp(BinaryOpType.eq, ex, new Literal(0), loc),
        new Literal(0), loc);
}

ASTSymbol parseExpressionLeaf(ref Parser parser)
{
    with (parser)
    {
        if (accept("*"))
        {
            mixin(ParserGuard!());
            auto next = parser.parseExpressionLeaf;

            assert(next !is null);
            return new ASTDereference(next);
        }
        if (accept("&"))
        {
            mixin(ParserGuard!());
            auto next = parser.parseExpressionLeaf;

            assert(next !is null);
            return new ASTReference(next);
        }
        if (parser.acceptIdentifier("new"))
        {
            mixin(ParserGuard!());
            auto type = parser.parseType;
            ASTSymbol[] args;
            if (accept("("))
            {
                args = parser.parseSymbolList;
            }

            return new ASTNewExpression(type, args, loc);
        }
        if (accept("!"))
        {
            mixin(ParserGuard!());
            auto next = parser.parseExpressionLeaf;

            assert(next !is null);
            return new ASTNegation(next, loc);
        }
        mixin(ParserGuard!());
        auto currentExpr = parser.parseExpressionBase;
        assert(currentExpr);
        return parser.parseProperties(currentExpr);
    }
}

ASTSymbol parseProperties(ref Parser parser, ASTSymbol current)
{
    while (true)
    {
        mixin(ParserGuard!());
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

    Loc loc;

    override Symbol compile(Context context)
    {
        auto base = this.base.compile(context).beExpression(loc);
        assert(cast(Class) base.type);
        auto target = cast(Class) this.target.compile(context);
        assert(target);
        return new PointerCast(target, base.accessMember("__instanceof", loc).call([new StringLiteral(target.name)], loc));
    }

    mixin(GenerateThis);
}

ASTSymbol parseInstanceOf(ref Parser parser, ASTSymbol left)
{
    mixin(ParserGuard!());
    with (parser) {
        begin;
        if (!(accept(".") && accept("instanceOf")))
        {
            revert;
            return null;
        }
        expect("(");
        auto type = parser.parseType;
        expect(")");
        commit;
        return new ASTInstanceOf(left, type, loc);
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

            if (text.front == '\\') {
                str ~= text.front;
                text.popFront;
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
            if (i == text.length) {
                assert(false, "unterminated control sequence");
            }
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
                case '"':
                    result ~= '"';
                    break;
                case '\\':
                    result ~= '\\';
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
        auto len = output.fun.wordLiteral(output.platform, this.text.length);
        auto ptr = output.fun.stringLiteral(this.text);

        return makeArray(output, type, len, ptr);
    }

    mixin(GenerateThis);
}

ASTSymbol parseExpressionBase(ref Parser parser)
{
    mixin(ParserGuard!());
    if (auto name = parser.parseIdentifier)
    {
        return new Variable(parser.loc, name);
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

    override string toString() const { return format!"(%s) %s"(target, value); }

    mixin(GenerateThis);
}

Expression implicitConvertTo(Expression from, Type to, Loc loc)
{
    if (from.type == to) return from;
    // void* casts to any pointer
    if (cast(Pointer) to && from.type == new Pointer(new Void))
    {
        return new PointerCast(to, from);
    }
    if (cast(Integer) from.type && cast(Long) to)
    {
        return new IntToLong(from);
    }
    // any pointer casts to void*
    if (cast(Pointer) from.type && to == new Pointer(new Void))
    {
        return new PointerCast(to, from);
    }
    // class casts to void*
    if (cast(Class) from.type && to == new Pointer(new Void))
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
    if (cast(Class) to && cast(NullExpr) from)
    {
        return new PointerCast(to, from);
    }
    loc.assert_(false, format!"todo: cast(%s) %s"(to, from.type));
    assert(false);
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

    bool override_;

    string name;

    Loc loc;

    @NonNull
    Type ret;

    Argument[] args;

    ASTStatement statement;

    @(This.Default!null)
    Statement compiledStatement;

    @(This.Init!false)
    bool emitted;

    string mangle()
    {
        // TODO mangle types
        return format!"_%s_%s"(this.classType.name, this.name);
    }

    void emit(Generator generator, Namespace module_, Class thisType)
    {
        assert(!this.emitted);
        this.emitted = true;

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
            argAssignments ~= argscope.declare(
                "this", thisType, new PointerCast(thisType, new ArgExpr(0, voidp)), Loc.init);
            foreach (i, arg; args)
            {
                auto argExpr = new ArgExpr(cast(int) i + 1, arg.type);

                argAssignments ~= argscope.declare(arg.name, arg.type, argExpr, Loc.init);
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
        Type thisp = classType;

        return new FunctionPointer(ret, [thisp] ~ args.map!(arg => arg.type).array);
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

    // will resolve members and methods as required
    ASTClassDecl decl;

    // used for resolving
    Context context;

    Member[] members;

    Method[] methods;

    Method[] vtable_; // methods appearing in the classinfo

    string vtableSymbol;

    this(ASTClassDecl decl, Class superClass, Context context)
    in (decl)
    {
        this.name = decl.name;
        this.superClass = superClass;
        this.decl = decl;
        this.context = context;
        this.members = null;
        this.methods = null;
    }

    void resolve()
    {
        // TODO only resolve once
        if (!decl) return;
        decl.compile2(context, this);
        decl = null;
    }

    bool resolved() { return this.decl is null; }

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
    in (resolved)
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
    in (resolved)
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
    in (resolved)
    {
        return new Struct(
            null,
            vtable.map!(a => Struct.Member(a.name, a.funcPtrType)).array,
        );
    }

    Method[] vtable() in (resolved) { return this.vtable_.dup; }

    void genVtable()
    {
        if (vtableSymbol) return;

        assert(!vtable_);

        Method[] combinedMethods;
        if (superClass)
        {
            superClass.genVtable;
            combinedMethods = superClass.vtable;
        }

        this.genInstanceofMethod;

        foreach (method; methods)
        {
            // TODO match types
            alias pred = a => a.name == method.name;
            bool isThis = method.name == "this"; // workaround: no final yet, no proper masking yet

            if (combinedMethods.any!pred)
            {
                method.loc.assert_(method.override_ || isThis,
                    "Expected 'override' attribute for overriding method.");
                combinedMethods[combinedMethods.countUntil!pred] = method;
            }
            else
            {
                method.loc.assert_(
                    !method.override_, "'override' specified but method does not override a parent method.");
                combinedMethods ~= method;
            }
        }
        vtable_ = combinedMethods;
        vtableSymbol = this.name ~ "_vtable";
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
            auto test = new ArrayEqual(target, new StringLiteral(current.name));

            castStmts ~= new IfStatement(test, new ReturnStatement(thisptr));
            current = current.superClass;
        }
        castStmts ~= new ReturnStatement(nullptr);

        auto stmt = new SequenceStatement(castStmts);

        bool override_ = superClass ? true : false;

        methods ~= new Method(this, override_, "__instanceof", Loc.init, voidp, [Argument("target", strng)], null, stmt);
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
        Loc loc;

        bool override_;

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

    Class compile(Context context)
    {
        Class superClass = null;
        if (this.superClass)
        {
            auto superClassObj = context.namespace.lookup(this.superClass);
            assert(superClassObj, format!"super class %s not found"(this.superClass));
            superClass = cast(Class) superClassObj;
            assert(superClass);
        }
        return new Class(this, superClass, context);
    }

    void compile2(Context context, Class target)
    {
        auto classScope = new ClassScope(context.namespace, target);
        auto classContext = context.withNamespace(classScope);

        target.members = this.members
            .map!(a => Class.Member(a.name, a.type.compile(classContext)))
            .array;
        target.methods = methods.map!(a => new .Method(
            target,
            a.override_,
            a.name,
            a.loc,
            a.ret.compile(classContext),
            a.args.map!(b => Argument(b.name, b.type.compile(classContext))).array,
            a.body_)).array;
        target.genVtable;
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
            strip;

            auto methodLoc = loc;

            ASTType retType;
            string memberName;
            bool override_ = parser.acceptIdentifier("override");

            if (accept("this"))
            {
                assert_(!override_, "cannot override constructor");
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
                methods ~= ASTClassDecl.Method(methodLoc, override_, memberName, retType, args, stmt);
            }
            else
            {
                assert_(!override_, "cannot override class member");
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

    Statement declare(string name, Type type, Expression value, Loc loc)
    {
        auto member = this.find!FunctionScope.declare(type);

        declarations ~= Variable(name, member);
        return new AssignStatement(member, value.implicitConvertTo(type, loc));
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

    Loc loc;

    mixin(GenerateThis);
}

ASTImport parseImport(ref Parser parser)
{
    if (!parser.accept("import"))
        return null;
    auto modname = parser.parseIdentifier(".");
    parser.expect(";");
    return new ASTImport(modname, parser.loc);
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
        // TODO each only once!
        foreach (import_; imports) import_.emit(generator);
        foreach (entry; entries)
        {
            if (auto class_ = cast(Class) entry.value)
            {
                class_.resolve;
                generator.mod.defineSymbolList(
                    class_.vtableSymbol, class_.vtable.map!(method => method.mangle).array);
            }
        }
        foreach (entry; entries)
        {
            if (auto fun = cast(Function) entry.value)
                if (!fun.declaration)
                    fun.emit(generator, Context(generator.platform, this));
            if (auto class_ = cast(Class) entry.value)
            {
                foreach (method; class_.methods)
                {
                    if (!method.emitted) method.emit(generator, this, class_);
                }
            }
        }
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

class ASTExtern
{
    string name;

    ASTType ret;

    ASTArgument[] args;

    Function compile(Context context)
    {
        auto args = this.args.map!(a => Argument(a.name, a.type.compile(context))).array;

        return new Function(name, this.ret.compile(context), args, true, null);
    }

    mixin(GenerateThis);
}

ASTExtern parseExtern(ref Parser parser)
{
    if (parser.accept("extern"))
    {
        parser.expect("(");
        parser.expect("C");
        parser.expect(")");
        ASTType ret = parser.parseType;
        string name = parser.parseIdentifier;
        if (!name) parser.fail("identifier expected");
        parser.expect("(");
        ASTArgument[] args = parser.parseIdentifierList;
        parser.expect(";");
        return new ASTExtern(name, ret, args);
    }
    return null;
}

string moduleToFile(string module_)
{
    return module_.replace(".", "/") ~ ".cx";
}

Module parseModule(
    string filename, string[] includes, Platform platform, Module[] defaultImports, ref Module[string] importCache,
    Loc loc = Loc.init)
{
    if (filename in importCache)
    {
        return importCache[filename];
    }
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
        loc.assert_(path.exists, format!"cannot find file '%s'"(filename));
    }
    string code = readText(path);
    auto parser = new Parser(path, code);

    parser.expect("module");
    auto modname = parser.parseIdentifier(".");
    parser.expect(";");

    assert(filename == modname.moduleToFile, format!"expected filename %s to match module %s"(filename, modname));
    auto module_ = new Module(null, modname);
    auto context = Context(platform, module_);

    defaultImports.each!(a => module_.addImport(a));

    while (!parser.eof)
    {
        if (auto import_ = parser.parseImport)
        {
            auto importedModule = parseModule(
                import_.name.moduleToFile, includes, platform, defaultImports, importCache, import_.loc);

            module_.addImport(importedModule);
            continue;
        }
        if (auto classDecl = parser.parseClassDecl)
        {
            module_.add(classDecl.name, classDecl.compile(context));
            continue;
        }
        if (auto extern_ = parser.parseExtern)
        {
            module_.add(extern_.name, extern_.compile(context));
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
    importCache[filename] = module_;
    return module_;
}

version (unittest) { }
else
{
    int main(string[] args)
    {
        import backend.interpreter : IpBackend;
        import core.memory : GC;

        // disable gc if you get random crashes
        GC.disable;

        string[] nextArgs;
        if (auto split = args.findSplit("--".only)) {
            args = split[0];
            nextArgs = split[2];
        }

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
        auto backend = new IpBackend;
        auto module_ = backend.createModule(defaultPlatform);

        builtins.add("string", new Array(new Character));
        builtins.add("bool", new Integer);
        builtins.add("true", new Literal(1));
        builtins.add("false", new Literal(0));
        builtins.add("null", new NullExpr(new Pointer(new Void)));
        switch (defaultPlatform.nativeWordSize) {
            case 4:
                builtins.add("size_t", new Integer);
                break;
            case 8:
                builtins.add("size_t", new Long);
                break;
            default:
                assert(false);
        }

        Module[string] importCache;

        auto toplevel = parseModule(args[1], includes, defaultPlatform, [builtins], importCache);

        auto output = new Generator(defaultPlatform, module_);

        toplevel.emit(output);

        // writefln!"module:\n%s"(module_);

        auto type = new Array(new Array(new Character));
        const size = type.emit(output.platform).size(output.platform);
        auto modArg = new void[size];
        *cast(string[]*) modArg = nextArgs;

        module_.call("main", null, [modArg]);
        // module_.dumpProfile;
        return 0;
    }
}
