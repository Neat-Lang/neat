module base;

import backend.backend;
import boilerplate;
import std.format;
import std.typecons;

interface ASTSymbol
{
    Symbol compile(Namespace namespace);
}

// something that can be referenced by a name
interface Symbol
{
}

interface ASTStatement
{
    Statement compile(Namespace namespace);
}

interface Statement
{
    void emit(Generator output);
}

Expression beExpression(Symbol symbol)
{
    if (auto expr = cast(Expression) symbol)
    {
        return expr;
    }
    assert(false, format!"expected expression, not %s"(symbol));
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

interface Expression : Symbol
{
    Type type();
    Reg emit(Generator output);
}

interface Reference : Expression
{
    Reg emitLocation(Generator output);
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
