module array;

import backend.backend;
import base;
import boilerplate;
import parser;
import std.algorithm;
import std.format : format;
import std.range;
import struct_;
import types;

class ASTArray : ASTType
{
    ASTType elementType;

    override Type compile(Namespace namespace)
    {
        return new Array(this.elementType.compile(namespace));
    }

    override string toString() const
    {
        return format!"%s[]"(this.elementType);
    }

    mixin(GenerateThis);
}

// ptr, length
class Array : Type
{
    Type elementType;

    // TODO remove; grab size from backend type!
    override size_t size() const
    {
        return 16;
    }

    override BackendType emit(BackendModule mod)
    {
        return mod.structType([
            mod.pointerType(this.elementType.emit(mod)),
            mod.intType]); // TODO mod.wordType / mod.wordSize
    }

    override string toString() const
    {
        return format!"%s[]"(this.elementType);
    }

    override bool opEquals(const Object other) const
    {
        auto otherArray = cast(Array) other;

        return otherArray && otherArray.elementType == elementType;
    }

    mixin(GenerateThis);
}

class ArrayLength : Expression
{
    Expression arrayValue;

    override Type type()
    {
        // TODO word type
        return new Integer;
    }

    override Reg emit(Generator output)
    {
        assert(cast(Reference) this.arrayValue, "TODO");
        auto arrayReg = (cast(Reference) this.arrayValue).emitLocation(output);
        auto lengthPtr = output.fun.fieldOffset(arrayValue.type.emit(output.mod), arrayReg, 1);
        return output.fun.load(type.emit(output.mod), lengthPtr);
    }

    mixin(GenerateThis);
}

class ArrayPointer : Expression
{
    Type elementType;

    Expression arrayValue;

    override Type type()
    {
        return new Pointer(this.elementType);
    }

    override Reg emit(Generator output)
    {
        assert(cast(Reference) this.arrayValue, "TODO");
        auto arrayReg = (cast(Reference) this.arrayValue).emitLocation(output);
        auto ptrPtr = output.fun.fieldOffset(arrayValue.type.emit(output.mod), arrayReg, 0);
        return output.fun.load(type.emit(output.mod), ptrPtr);
    }

    mixin(GenerateThis);
}

class ASTArrayLiteral : ASTSymbol
{
    ASTSymbol[] elements;

    override ArrayLiteral compile(Namespace namespace)
    {
        Expression[] expressions;
        Type elementType;
        foreach (element; elements)
        {
            auto newExpression = element.compile(namespace).beExpression;
            if (!elementType) elementType = newExpression.type;
            else assert(newExpression.type == elementType);
            expressions ~= newExpression;
        }
        if (!elementType) assert(false, "cannot type empty literal");
        return new ArrayLiteral(elementType, expressions);
    }

    override string toString() const
    {
        return format!"[%(%s, %)]"(this.elements);
    }

    mixin(GenerateThis);
}

class ArrayLiteral : Expression
{
    Type elementType;

    Expression[] expressions;

    override Type type()
    {
        return new Array(elementType);
    }

    override Reg emit(Generator output)
    {
        auto voidp = output.mod.pointerType(output.mod.voidType);
        int memSize = cast(int) elementType.size * cast(int) this.expressions.length; // TODO alignment

        Reg len = output.fun.intLiteral(cast(int) this.expressions.length);
        Reg ptr = output.fun.call(voidp, "malloc", [output.fun.intLiteral(memSize)]);
        foreach (i, expression; expressions)
        {
            int ptrOffset = cast(int) elementType.size * cast(int) i;

            Reg valueReg = expression.emit(output);
            Reg ptrOffsetReg = output.fun.call(voidp, "ptr_offset", [ptr, output.fun.intLiteral(ptrOffset)]);

            output.fun.store(elementType.emit(output.mod), ptrOffsetReg, valueReg);
        }
        auto structType = type.emit(output.mod);
        // TODO allocaless
        Reg structReg = output.fun.alloca(structType);
        Reg ptrField = output.fun.fieldOffset(structType, structReg, 0);
        Reg lenField = output.fun.fieldOffset(structType, structReg, 1);

        output.fun.store(voidp, ptrField, ptr);
        output.fun.store(output.mod.intType, lenField, len);
        return output.fun.load(structType, structReg);
    }

    mixin(GenerateThis);
}
