module base;

import backend.backend;
import backend.platform;
import backend.types;
import boilerplate;
import std.format;
import std.typecons;

struct Context
{
    Platform platform;

    Namespace namespace;

    Context withNamespace(Namespace namespace)
    {
        return Context(platform, namespace);
    }
}

interface ASTSymbol
{
    Symbol compile(Context context);
}

// something that can be referenced by a name
interface Symbol
{
}

interface ASTStatement
{
    Statement compile(Context context);
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
    abstract BackendType emit(Platform);

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

    @NonNull
    Platform platform;

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

    this(Platform platform, BackendModule mod, BackendFunction fun = null)
    {
        this.platform = platform;
        this.mod = mod;
        this.fun = fun;
    }
}
