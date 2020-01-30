module hello;

import boilerplate;
import std.algorithm;
import std.range;
import std.string;
import std.stdio;
import std.uni;

// something that can be referenced by a name
interface Symbol {}

struct Value {
    enum Type {
        undef,
        integer,
        symbol,
    }
    Type type;
    union {
        int integer;
        Symbol symbol;
    }
    bool truthy() {
        return this.type == Type.integer && this.integer != 0;
    }

    string toString() const {
        import std.conv : to;

        final switch (this.type) {
            case Type.integer: return this.integer.to!string;
            case Type.symbol: return this.symbol.to!string;
            case Type.undef: return "<undef>";
        }
    }

    this(int integer) {
        this.type = Type.integer;
        this.integer = integer;
    }

    this(Symbol symbol) {
        this.type = Type.symbol;
        this.symbol = symbol;
    }

    static Value undef() {
        Value value;
        value.type = Type.undef;
        return value;
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

class Function : Symbol
{
    string name;

    Type type;

    Argument[] args;

    Statement statement;

    @(This.Init!null)
    Scope scope_; // bound scope

    mixin(GenerateThis);
    mixin(GenerateToString);
}

struct ControlFlow
{
    enum Type {
        pass,
        return_,
    }
    Type type;
    bool isPass() { return type == Type.pass; }
    bool isReturn() { return type == Type.return_; }
    static ControlFlow pass() { return ControlFlow(Type.pass); }
    static ControlFlow return_(Value v) {
        ControlFlow cf = ControlFlow(Type.return_);
        cf.value = v;
        return cf;
    }
    union {
        Value value;
    }
}

interface Statement {
    ControlFlow interpret(Scope);
}

interface Expression {
    Value interpret(Scope);
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

    override ControlFlow interpret(Scope scope_) {
        auto subscope = Scope.alloc(scope_);
        foreach (statement; statements) {
            auto effect = statement.interpret(subscope);
            if (effect.isReturn) {
                subscope.release;
                return effect;
            }
        }
        subscope.release;
        return ControlFlow.pass;
    }
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

    override ControlFlow interpret(Scope scope_) {
        return ControlFlow.return_(value.interpret(scope_));
    }

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

    override ControlFlow interpret(Scope scope_) {
        auto value = test.interpret(scope_);
        if (value.truthy) {
            auto subscope = Scope.alloc(scope_);
            auto res = then.interpret(subscope);
            subscope.release;
            return res;
        }
        return ControlFlow.pass;
    }

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

    override Value interpret(Scope scope_) {
        auto leftval = this.left.interpret(scope_);
        auto rightval = this.right.interpret(scope_);
        assert(leftval.type == Value.Type.integer);
        assert(rightval.type == Value.Type.integer);
        final switch (this.op) {
            case Op.add:
                return Value(leftval.integer + rightval.integer);
            case Op.sub:
                return Value(leftval.integer - rightval.integer);
            case Op.eq:
                return Value(leftval.integer == rightval.integer);
        }
    }

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

    override Value interpret(Scope scope_) {
        auto funvalue = scope_.lookup(name);
        assert(funvalue.type == Value.Type.symbol);
        auto fun = cast(Function) funvalue.symbol;
        assert(fun, "no such function: " ~ name);
        Value[] values;
        foreach (arg; this.args) {
            values ~= arg.interpret(scope_);
        }
        return interpret_call(fun, values);
    }

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

    override Value interpret(Scope scope_) {
        auto value = scope_.lookup(name);
        assert(value.type != Value.Type.undef, "no such variable: " ~ name);
        return value;
    }

    mixin(GenerateThis);
    mixin(GenerateToString);
}

class Literal : Expression
{
    int value;

    override Value interpret(Scope) {
        return Value(this.value);
    }

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

class Scope
{
    Scope parent;

    ref Scope freelist() { return this.parent; }

    size_t refs;

    struct Variable
    {
        string name;

        Value value;
    }
    Appender!(Variable[]) vars;

    static Scope freelistHead = null;

    static Scope alloc(Scope parent = null)
    {
        if (parent) parent.claim;
        if (freelistHead is null) {
            auto scope_ = new Scope;
            scope_.parent = parent;
            scope_.refs = 1;
            scope_.vars.clear;
            return scope_;
        }
        auto scope_ = freelistHead;
        freelistHead = freelistHead.freelist;
        scope_.parent = parent;
        scope_.refs = 1;
        scope_.vars.clear;
        return scope_;
    }

    void claim() {
        this.refs ++;
    }

    void release() {
        assert(this.refs > 0);
        this.refs --;
        if (this.refs == 0) {
            if (this.parent) this.parent.release;
            this.freelist = freelistHead;
            freelistHead = this;
        }
    }

    void add(string name, Value value) {
        assert(!this.vars.data().any!(var => var.name == name));
        this.vars ~= Variable(name, value);
    }

    Value lookup(string name) {
        foreach (var; this.vars) {
            if (var.name == name) return var.value;
        }
        if (this.parent) return this.parent.lookup(name);
        return Value.undef;
    }
}

Value interpret_call(Function function_, Value[] args)
{
    auto callscope = Scope.alloc(function_.scope_);

    foreach (arg, value; function_.args.zip(args))
    {
        callscope.add(arg.name, value);
    }
    auto effect = function_.statement.interpret(callscope);
    callscope.release;
    if (effect.isReturn) return effect.value;
    assert(false, "missing return");
}

void main() {
    writefln!"running.";

    string code = "int ack(int m, int n) {
        if (m == 0) return n + 1;
        if (n == 0) return ack(m - 1, 1);
        return ack(m - 1, ack(m, n - 1));
    }";
    auto parser = new Parser(code);
    auto fun = parser.parseFunction;
    // assert(parser.eof);

    writefln!"%s"(fun);

    auto scope_ = Scope.alloc;

    scope_.add("ack", Value(fun));
    fun.scope_ = scope_;

    for (int i = 0; i < 10; i++) {
        auto ret = interpret_call(fun, [Value(3), Value(8)]);

        writefln!"ack(3, 8) = %s"(ret);
    }
}
