module hello;

import boilerplate;
import std.algorithm;
import std.range;
import std.string;
import std.stdio;
import std.uni;

// something that can be referenced by a name
interface Symbol {}

class Type
{
    override string toString() const { assert(false); }
}

class Integer : Type
{
    override string toString() const { return "int"; }
}

extern(C) {
    struct Data {
        void* ptr;
        size_t length;
    }
    Data *alloc_data();
    size_t begin_declare_section(void* data);
    void* begin_define_section(size_t index);
    void end_define_section(Data* data, void* state);
    void declare_symbol(void* data, int args);
    void add_string(void* data, const char* text);
    void add_type_int(Data* data);
    void end_declare_section(void* data, size_t offset);

    void add_ret_instr(void* state, int reg);
    int add_tbr_instr(void* state, int reg);
    int add_literal_instr(void* state, int value);
    int add_arg_instr(void* state, int index);
    void tbr_resolve_then(void* state, int tbr_offset, int block);
    void tbr_resolve_else(void* state, int tbr_offset, int block);
    int add_br_instr(void* state);
    void br_resolve(void* state, int br_offset, int block);
    int start_call_instr(void* state, int offset, int args);
    void add_call_reg_arg(void* state, int reg);
    int start_block(void* state);
}

class Generator {
    Data* mainFile;
    void* defineSection;

    invariant(mainFile !is null);

    int numDeclarations;

    this(Data* mainFile, Data* defineSection = null) {
        this.mainFile = mainFile;
        this.defineSection = defineSection;
    }

    template opDispatch(string name) {
        auto opDispatch(T...)(T args) {
            static string member() {
                switch (name) {
                    case "add_string":
                    case "add_type_int":
                    case "declare_symbol":
                    case "begin_declare_section":
                    case "end_declare_section":
                        return "this.mainFile";
                    default: return "this.defineSection";
                }
            }
            return mixin(name ~ "(" ~ member() ~ ", args)");
        }
    }
}

int gen_int_stub(string op)(Generator gen) {
    size_t start = gen.begin_declare_section;
    gen.declare_symbol(2);
    gen.add_string(toStringz("int_" ~ op));
    gen.add_type_int; // ret
    gen.add_type_int;
    gen.add_type_int;
    gen.end_declare_section(start);
    return gen.numDeclarations++;
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

    Type ret;

    Argument[] args;

    Statement statement;

    @(This.Init!(-1))
    int decl_offset;

    @(This.Init!null)
    Scope scope_; // bound scope

    mixin(GenerateThis);
    mixin(GenerateToString);
}

void add_type(Data* data, Type type) {
    if (cast(Integer) type) {
        add_type_int(data);
        return;
    }
    assert(false);
}

int declare(Generator output, Function fun) {
    if (fun.decl_offset != -1) return fun.decl_offset;
    size_t section = begin_declare_section(output.mainFile);
    declare_symbol(output.mainFile, cast(int) fun.args.length);
    add_string(output.mainFile, fun.name.toStringz);
    add_type(output.mainFile, fun.ret);
    foreach (arg; fun.args) {
        add_type(output.mainFile, arg.type);
    }
    end_declare_section(output.mainFile, section);
    fun.decl_offset = output.numDeclarations++;
    return fun.decl_offset;
}

interface Statement {
    void emit(Scope scope_, Generator output);
}

interface Expression : Symbol {
    int emit(Scope scope_, Generator output);
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

    override void emit(Scope scope_, Generator output) {
        auto subscope = new Scope(scope_);
        foreach (statement; statements) {
            statement.emit(subscope, output);
        }
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

    override void emit(Scope scope_, Generator output) {
        int reg = this.value.emit(scope_, output);
        output.add_ret_instr(reg);
        output.start_block;
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

    override void emit(Scope scope_, Generator output) {
        int reg = test.emit(scope_, output);
        int tbr_offset = output.add_tbr_instr(reg);
        int thenblk = output.start_block;
        output.tbr_resolve_then(tbr_offset, thenblk);
        auto subscope = new Scope(scope_);
        then.emit(subscope, output);
        int after_then = output.add_br_instr;
        // TODO else blk
        int afterblk = output.start_block;
        output.tbr_resolve_else(tbr_offset, afterblk);
        output.br_resolve(after_then, afterblk);
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

    override int emit(Scope scope_, Generator output) {
        int leftreg = this.left.emit(scope_, output);
        int rightreg = this.right.emit(scope_, output);
        int offset = {
            final switch (this.op) {
                case Op.add:
                    return gen_int_stub!"add"(output);
                case Op.sub:
                    return gen_int_stub!"sub"(output);
                case Op.eq:
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

    override int emit(Scope scope_, Generator output) {
        auto funsym = scope_.lookup(name);
        int fun_offset = declare(output, cast(Function) funsym);
        int[] regs;
        foreach (arg; this.args) {
            regs ~= arg.emit(scope_, output);
        }
        int callreg = output.start_call_instr(fun_offset, cast(int) this.args.length);
        foreach (reg; regs) {
            output.add_call_reg_arg(reg);
        }
        return callreg;
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

    override int emit(Scope scope_, Generator output) {
        auto sym = scope_.lookup(name);
        assert(sym, format!"unknown name %s"(name));
        auto expr = cast(Expression) sym;
        assert(expr, format!"%s"(sym));
        return expr.emit(scope_, output);
    }

    mixin(GenerateThis);
    mixin(GenerateToString);
}

class Literal : Expression
{
    int value;

    override int emit(Scope, Generator output) {
        return output.add_literal_instr(this.value);
    }

    override string toString() const {
        import std.conv : to;

        return value.to!string;
    }

    mixin(GenerateThis);
}

class ArgExpr : Expression
{
    int index;

    override int emit(Scope, Generator output) {
        return output.add_arg_instr(this.index);
    }

    override string toString() const {
        import std.format : format;

        return format!"%%%s"(this.index);
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

    this(Scope parent) {
        this.parent = parent;
    }

    struct Variable
    {
        string name;

        Symbol value;
    }
    Appender!(Variable[]) vars;

    void add(string name, Symbol value) {
        assert(!this.vars.data().any!(var => var.name == name));
        this.vars ~= Variable(name, value);
    }

    Symbol lookup(string name) {
        foreach (var; this.vars) {
            if (var.name == name) return var.value;
        }
        if (this.parent) return this.parent.lookup(name);
        return null;
    }
}

class BytecodeFile {
    Generator generator;
    this() {
        this.generator = new Generator(alloc_data());
    }
    void define(Function fun, Scope scope_) {
        int declid = declare(this.generator, fun);
        assert(this.generator.defineSection is null);
        this.generator.defineSection = begin_define_section(declid);
        this.generator.start_block;
        auto funscope = new Scope(scope_);
        foreach (i, arg; fun.args) {
            funscope.add(arg.name, new ArgExpr(cast(int) i));
        }
        fun.statement.emit(funscope, this.generator);
        end_define_section(this.generator.mainFile, this.generator.defineSection);
        this.generator.defineSection = null;
    }
    void writeTo(string filename) {
        static import std.file;

        std.file.write(filename, (cast(ubyte*) this.generator.mainFile.ptr)[0 .. this.generator.mainFile.length]);
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
    // assert(parser.eof);

    writefln!"%s"(fun);

    auto scope_ = new Scope(null);

    scope_.add("ack", fun);
    auto output = new BytecodeFile;
    output.define(fun, scope_);
    output.writeTo("ack.bc");
}
