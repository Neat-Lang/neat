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
        const int elementSize = arrayType.elementType.emit(output.platform).size(output.platform);

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
