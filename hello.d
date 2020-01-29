module hello;

import boilerplate;
import std.range;
import std.string;
import std.stdio;
import std.uni;

struct Value {
    enum Type {
        integer,
    }
    Type type;
    union {
        int i;
    }
}

class Type
{
    override string toString() const { assert(false); }
}

class Integer : Type
{
    override string toString() const { return "int"; }
}

class Parser
{
    string[] stack;

    invariant(!this.stack.empty);

    size_t level;

    invariant(this.level <= this.stack.length);

    @property ref string text() {
        return this.stack[this.level];
    }

    void begin() {
        if (this.level == this.stack.length - 1) {
            this.stack ~= this.text;
        } else {
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

    this(string text) {
        this.stack ~= text;
    }

    bool accept(string match) {
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

    void expect(string match) {
        if (!accept(match)) {
            fail(format!"'%s' expected."(match));
        }
    }

    void fail(string msg) {
        assert(false, format!"at %s: %s"(this.text, msg));
    }

    void strip() {
        this.text = this.text.strip;
    }
}

bool parseNumber(ref Parser parser, out int i) {
    import std.conv : to;

    with (parser) {
        begin;
        strip;
        if (text.empty || !text.front.isNumber) {
            revert;
            return false;
        }
        string number;
        while (!text.empty && text.front.isNumber) {
            number ~= text.front;
            text.popFront;
        }
        commit;
        i = number.to!int;
        return true;
    }
}

string parseIdentifier(ref Parser parser) {
    with (parser) {
        begin;
        strip;
        if (text.empty || !text.front.isAlpha) {
            revert;
            return null;
        }
        string identifier;
        while (!text.empty && text.front.isAlphaNum) {
            identifier ~= text.front;
            text.popFront;
        }
        commit;
        return identifier;
    }
}

Type parseType(ref Parser parser) {
    with (parser) {
        begin;

        if (parser.parseIdentifier == "int") {
            commit;
            return new Integer;
        }

        fail("unknown type");
        assert(false);
    }
}

struct Argument
{
    Type type;
    string name;
}

// something that can be referenced by a name
interface Symbol {}

class Function : Symbol
{
    string name;

    Type type;

    Argument[] args;

    Statement statement;

    mixin(GenerateThis);
    mixin(GenerateToString);
}

interface Statement {
}

interface Expression {
}

Function parseFunction(ref Parser parser) {
    with (parser) {
        begin;
        auto ret = parser.parseType;
        auto name = parser.parseIdentifier;
        expect("(");
        Argument[] args;
        while (!accept(")")) {
            if (!args.empty) {
                if (!accept(",")) {
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

class SequenceStatement : Statement {
    Statement[] statements;

    mixin(GenerateThis);
    mixin(GenerateToString);
}

SequenceStatement parseSequence(ref Parser parser) {
    with (parser) {
        begin;
        if (!accept("{")) {
            revert;
            return null;
        }
        Statement[] statements;
        while (!accept("}")) {
            auto stmt = parser.parseStatement;
            statements ~= stmt;
        }
        commit;
        return new SequenceStatement(statements);
    }
}

class ReturnStatement : Statement {
    Expression value;

    mixin(GenerateThis);
    mixin(GenerateToString);
}

ReturnStatement parseReturn(ref Parser parser) {
    with (parser) {
        begin;
        if (parser.parseIdentifier != "return") {
            revert;
            return null;
        }
        auto expr = parser.parseExpression;
        expect(";");
        commit;
        return new ReturnStatement(expr);
    }
}

class IfStatement : Statement {
    Expression test;
    Statement then;

    mixin(GenerateThis);
    mixin(GenerateToString);
}

IfStatement parseIf(ref Parser parser) {
    with (parser) {
        begin;
        if (parser.parseIdentifier != "if") {
            revert;
            return null;
        }
        parser.expect("(");
        auto expr = parser.parseExpression;
        parser.expect(")");
        auto thenStmt = parser.parseStatement;
        commit;
        return new IfStatement(expr, thenStmt);
    }
}

Statement parseStatement(ref Parser parser) {
    if (auto stmt = parser.parseReturn) return stmt;
    if (auto stmt = parser.parseIf) return stmt;
    if (auto stmt = parser.parseSequence) return stmt;
    parser.fail("statement expected");
    assert(false);
}

Expression parseExpression(ref Parser parser) {
    if (auto expr = parser.parseCall) {
        return expr;
    }

    return parser.parseArithmetic;
}

class ArithmeticOp : Expression {
    enum Op {
        add,
        sub,
        eq,
    }
    Op op;
    Expression left;
    Expression right;

    mixin(GenerateThis);
    mixin(GenerateToString);
}

Expression parseArithmetic(ref Parser parser, size_t level = 0) {
    auto left = parser.parseExpressionLeaf;
    if (level <= 1) {
        parseAddSub(parser, left);
    }
    if (level == 0) {
        parseComparison(parser, left);
    }
    return left;
}

void parseAddSub(ref Parser parser, ref Expression left) {
    while (true) {
        if (parser.accept("+")) {
            auto right = parser.parseExpressionLeaf;
            left = new ArithmeticOp(ArithmeticOp.Op.add, left, right);
            continue;
        }
        if (parser.accept("-")) {
            auto right = parser.parseExpressionLeaf;
            left = new ArithmeticOp(ArithmeticOp.Op.sub, left, right);
            continue;
        }
        break;
    }
}

void parseComparison(ref Parser parser, ref Expression left) {
    if (parser.accept("==")) {
        auto right = parser.parseArithmetic(1);
        left = new ArithmeticOp(ArithmeticOp.Op.eq, left, right);
    }
}

class Call : Expression {
    string name;
    Expression[] args;

    mixin(GenerateThis);
    mixin(GenerateToString);
}

Expression parseCall(ref Parser parser) {
    with (parser) {
        begin;
        auto name = parser.parseIdentifier;
        if (!name || !accept("(")) {
            revert;
            return null;
        }
        Expression[] args;
        while (!accept(")")) {
            if (!args.empty) expect(",");
            args ~= parser.parseExpression;
        }
        commit;
        return new Call(name, args);
    }
}

class Variable : Expression
{
    string name;

    mixin(GenerateThis);
    mixin(GenerateToString);
}

class Literal : Expression
{
    int value;

    override string toString() const {
        import std.conv : to;

        return value.to!string;
    }

    mixin(GenerateThis);
}

Expression parseExpressionLeaf(ref Parser parser) {
    with (parser) {
        if (auto name = parser.parseIdentifier) {
            return new Variable(name);
        }
        int i;
        if (parser.parseNumber(i)) {
            return new Literal(i);
        }
        fail("Expression expected.");
        assert(false);
    }
}

void main() {
    string code = "int ack(int m, int n) {
        if (m == 0) return n + 1;
        if (n == 0) return ack(m - 1, 1);
        return ack(m - 1, ack(m, n - 1));
    }";
    auto parser = new Parser(code);
    auto fun = parser.parseFunction;

    writefln!"%s"(fun);

    // assert(parser.eof);
    // interpret(fun, 3, 4);
}
