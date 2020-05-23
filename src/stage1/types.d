module types;

import backend.backend;
import base;
import boilerplate;
import parser;
import std.algorithm;
import std.format;
import std.range;

interface ASTType
{
    Type compile(Namespace namespace);
}

class ASTInteger : ASTType
{
    override Integer compile(Namespace) {
        return new Integer;
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

class ASTCharType : ASTType
{
    override Character compile(Namespace) {
        return new Character;
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

class ASTVoid : ASTType
{
    override Void compile(Namespace) {
        return new Void;
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

class NamedType : ASTType
{
    string name;
    invariant(name.length);

    override Type compile(Namespace namespace)
    {
        auto target = namespace.lookup(this.name);

        assert(cast(Type) target, format!"target for '%s' = %s"(this.name, target));
        return cast(Type) target;
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

ASTType parseLeafType(ref Parser parser)
{
    with (parser)
    {
        begin;

        auto identifier = parser.parseIdentifier;
        if (!identifier)
        {
            revert;
            return null;
        }

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
