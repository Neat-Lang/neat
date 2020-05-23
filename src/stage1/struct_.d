module struct_;

import backend.backend;
import base;
import boilerplate;
import parser;
import std.algorithm;
import std.format;
import std.range;
import types;

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
