module types;

import backend.backend;
import backend.platform;
import backend.types;
import base;
import boilerplate;
import parser;
import std.algorithm;
import std.format;
import std.range;

interface ASTType
{
    Type compile(Context context);
}

class ASTInteger : ASTType
{
    override Integer compile(Context) {
        return new Integer;
    }
}

class Integer : Type
{
    override BackendType emit(Platform)
    {
        return new BackendIntType;
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
    override Character compile(Context) {
        return new Character;
    }
}

class Character : Type
{
    override BackendType emit(Platform)
    {
        return new BackendCharType;
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
    override Void compile(Context) {
        return new Void;
    }
}

class Void : Type
{
    override BackendType emit(Platform)
    {
        return new BackendVoidType;
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

    override Type compile(Context context)
    {
        auto subType = this.subType.compile(context);

        return new Pointer(subType);
    }

    mixin(GenerateThis);
}

class Pointer : Type
{
    Type target;

    override BackendType emit(Platform platform)
    {
        return new BackendPointerType(target.emit(platform));
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

    override Type compile(Context context)
    {
        auto ret = this.ret.compile(context);
        auto args = this.args.map!(a => a.compile(context)).array;

        return new FunctionPointer(ret, args);
    }

    mixin(GenerateThis);
}

class FunctionPointer : Type
{
    Type ret;

    Type[] args;

    override BackendType emit(Platform platform)
    {
        return new BackendFunctionPointerType(
            ret.emit(platform),
            args.map!(a => a.emit(platform)).array);
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

    Loc loc;

    override Type compile(Context context)
    {
        auto target = context.namespace.lookup(this.name);

        loc.assert_(cast(Type) target, format!"target for '%s' = %s"(this.name, target));
        return cast(Type) target;
    }

    mixin(GenerateThis);
}

ASTType parseType(ref Parser parser)
{
    mixin(ParserGuard!());
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

            begin;
            if (accept("[") && accept("]"))
            {
                commit;
                import array : ASTArray;
                current = new ASTArray(current);
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
    mixin(ParserGuard!());
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

        commit;
        return new NamedType(identifier, loc);
    }
}
