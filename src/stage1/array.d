module array;

import backend.backend;
import backend.platform;
import backend.types;
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

    override Type compile(Context context)
    {
        return new Array(this.elementType.compile(context));
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

    override BackendType emit(Platform platform)
    {
        return new BackendStructType([
            cast(BackendType) new BackendPointerType(this.elementType.emit(platform)),
            cast(BackendType) new BackendIntType]); // TODO mod.wordType / mod.wordSize
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
        auto arrayReg = this.arrayValue.emit(output);
        return output.fun.field(arrayValue.type.emit(output.platform), arrayReg, 1);
    }

    mixin(GenerateThis);
}

Reg getArrayPointer(Generator output, Type arrayType, Reg arrayReg)
{
    return output.fun.field(arrayType.emit(output.platform), arrayReg, 0);
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
        auto arrayReg = this.arrayValue.emit(output);
        return getArrayPointer(output, this.arrayValue.type, arrayReg);
    }

    mixin(GenerateThis);
}

class ASTArrayLiteral : ASTSymbol
{
    Loc loc;

    struct Entry
    {
        ASTSymbol symbol;

        bool spread;
    }

    Entry[] elements;

    override ArrayLiteral compile(Context context)
    {
        ArrayLiteral.Element[] elements;
        Type elementType;
        foreach (entry; this.elements)
        {
            auto newExpression = entry.symbol.compile(context).beExpression;
            Type expressionElementType;
            if (entry.spread)
            {
                auto subtype = cast(Array) newExpression.type;
                assert(subtype, "spread entry must be array");
                expressionElementType = subtype.elementType;
            }
            else
            {
                expressionElementType = newExpression.type;
            }
            if (!elementType) elementType = expressionElementType;
            else loc.assert_(expressionElementType == elementType, "unexpected element type");
            elements ~= ArrayLiteral.Element(newExpression, entry.spread);
        }
        if (!elementType) assert(false, "cannot type empty literal");
        return new ArrayLiteral(elementType, elements);
    }

    override string toString() const
    {
        return format!"[%(%s, %)]"(this.elements);
    }

    mixin(GenerateThis);
}

class ArrayExpression : Expression
{
    Expression pointer;

    Expression length;

    override Type type()
    {
        auto ptrType = cast(Pointer) this.pointer.type;
        assert(ptrType);
        return new Array(ptrType.target);
    }

    override Reg emit(Generator output)
    {
        auto pointer = this.pointer.emit(output);
        auto length = this.length.emit(output);
        auto voidp = (new Pointer(new Void)).emit(output.platform);
        auto intType = (new Integer).emit(output.platform);

        // TODO allocaless
        auto structType = this.type.emit(output.platform);
        Reg structReg = output.fun.alloca(structType);
        Reg ptrField = output.fun.fieldOffset(structType, structReg, 0);
        Reg lenField = output.fun.fieldOffset(structType, structReg, 1);

        output.fun.store(voidp, ptrField, pointer);
        output.fun.store(intType, lenField, length);
        return output.fun.load(structType, structReg);
    }

    mixin(GenerateThis);
}

class ArrayLiteral : Expression
{
    struct Element
    {
        Expression expression;

        bool spread;
    }
    Type elementType;

    // TODO rename to Component
    Element[] elements;

    override Type type()
    {
        return new Array(elementType);
    }

    override Reg emit(Generator output)
    {
        auto voidp = new BackendPointerType(new BackendVoidType);
        auto intType = new BackendIntType;

        Reg lenPtr = output.fun.alloca(intType); // TODO word type
        const numNonSpreadElements = this.elements.filter!(a => !a.spread).count;
        output.fun.store(intType, lenPtr, output.fun.intLiteral(cast(int) numNonSpreadElements));

        // add the lengths of each array element
        foreach (i, element; this.elements)
        {
            if (element.spread)
            {
                Reg len = output.fun.load(intType, lenPtr);
                // TODO prevent double emit when we can have non-ref struct base
                Reg addLen = (new ArrayLength(element.expression)).emit(output);
                Reg sumLen = output.fun.binop("+", len, addLen);
                output.fun.store(intType, lenPtr, sumLen);
            }
        }
        const int arrayElementSize = output.platform.size(this.elementType.emit(output.platform));
        Reg memSize = output.fun.binop("*", output.fun.load(intType, lenPtr), output.fun.intLiteral(arrayElementSize));

        Reg ptr = output.fun.call(voidp, "malloc", [memSize]);
        Reg currentOffsetPtr = output.fun.alloca(intType);
        output.fun.store(intType, currentOffsetPtr, output.fun.intLiteral(0));

        foreach (i, element; this.elements)
        {
            Reg currentOffset = output.fun.load(intType, currentOffsetPtr);
            Reg ptrOffsetReg = output.fun.call(voidp, "ptr_offset", [ptr, currentOffset]);

            if (element.spread)
            {
                // TODO prevent double emit when we can have non-ref struct base
                Reg elementLen = (new ArrayLength(element.expression)).emit(output);
                Reg elementPtr = (new ArrayPointer(this.elementType, element.expression)).emit(output);
                Reg elementSize = output.fun.binop("*", elementLen, output.fun.intLiteral(arrayElementSize));

                output.fun.call(voidp, "memcpy", [ptrOffsetReg, elementPtr, elementSize]);
                output.fun.store(intType, currentOffsetPtr,
                    output.fun.binop("+", currentOffset, elementSize));
            }
            else
            {
                output.fun.store(elementType.emit(output.platform), ptrOffsetReg, element.expression.emit(output));
                output.fun.store(intType, currentOffsetPtr,
                    output.fun.binop("+", currentOffset, output.fun.intLiteral(arrayElementSize)));
            }
        }
        auto structType = type.emit(output.platform);
        // TODO allocaless
        Reg structReg = output.fun.alloca(structType);
        Reg ptrField = output.fun.fieldOffset(structType, structReg, 0);
        Reg lenField = output.fun.fieldOffset(structType, structReg, 1);

        output.fun.store(voidp, ptrField, ptr);
        output.fun.store(intType, lenField, output.fun.load(intType, lenPtr));
        return output.fun.load(structType, structReg);
    }

    mixin(GenerateThis);
}

class ASTArraySlice : ASTSymbol
{
    ASTSymbol array;

    ASTSymbol lower;

    ASTSymbol upper;

    override ArraySlice compile(Context context)
    {
        return new ArraySlice(
            this.array.compile(context).beExpression,
            this.lower.compile(context).beExpression,
            this.upper.compile(context).beExpression);
    }

    override string toString() const
    {
        return format!"%s[%s .. %s]"(array, lower, upper);
    }

    mixin(GenerateThis);
}

class ArraySlice : Expression
{
    Expression array;

    Expression lower;

    Expression upper;

    override Type type() { return this.array.type; }

    override Reg emit(Generator output)
    {
        auto voidp = new BackendPointerType(new BackendVoidType);
        auto intType = new BackendIntType;

        auto arrayType = cast(Array) this.array.type;
        assert(arrayType, "slice of non-array");
        const int elementSize = output.platform.size(arrayType.elementType.emit(output.platform));

        auto arrayReg = this.array.emit(output);
        auto lowerReg = this.lower.emit(output);
        auto upperReg = this.upper.emit(output);
        auto ptr = getArrayPointer(output, arrayType, arrayReg);
        // ptr = ptr + lower
        Reg lowerOffset = output.fun.binop("*", lowerReg, output.fun.intLiteral(elementSize));
        Reg newPtr = output.fun.call(voidp, "ptr_offset", [ptr, lowerOffset]);
        // len = upper - lower
        Reg newLen = output.fun.binop("-", upperReg, lowerReg);

        // TODO allocaless
        auto structType = arrayType.emit(output.platform);
        Reg structReg = output.fun.alloca(structType);
        Reg ptrField = output.fun.fieldOffset(structType, structReg, 0);
        Reg lenField = output.fun.fieldOffset(structType, structReg, 1);

        output.fun.store(voidp, ptrField, newPtr);
        output.fun.store(intType, lenField, newLen);
        return output.fun.load(structType, structReg);
    }

    mixin(GenerateThis);
}
