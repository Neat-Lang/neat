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

// length, ptr
class Array : Type
{
    Type elementType;

    override BackendType emit(Platform platform)
    {
        // layout matches D arrays for efficiency
        return new BackendStructType([
            cast(BackendType) platform.backendWordType,
            cast(BackendType) new BackendPointerType(this.elementType.emit(platform))]);
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

Reg getArrayLen(Generator output, Type arrayType, Reg arrayReg)
{
    return output.fun.field(arrayType.emit(output.platform), arrayReg, 0);
}

class ArrayLength : Expression
{
    Expression arrayValue;

    Type type_;

    override Type type()
    {
        return type_;
    }

    override Reg emit(Generator output)
    {
        auto arrayReg = this.arrayValue.emit(output);

        return getArrayLen(output, arrayValue.type, arrayReg);
    }

    mixin(GenerateThis);
}

Reg getArrayPtr(Generator output, Type arrayType, Reg arrayReg)
{
    return output.fun.field(arrayType.emit(output.platform), arrayReg, 1);
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
        return getArrayPtr(output, this.arrayValue.type, arrayReg);
    }

    mixin(GenerateThis);
}

int makeArray(Generator output, Type arrayType, int lenReg, int ptrReg)
{
    auto voidp = (new Pointer(new Void)).emit(output.platform);
    auto wordType = output.platform.backendWordType;

    // TODO allocaless
    auto structType = arrayType.emit(output.platform);
    int structReg = output.fun.alloca(structType);
    int lenField = output.fun.fieldOffset(structType, structReg, 0);
    int ptrField = output.fun.fieldOffset(structType, structReg, 1);

    output.fun.store(wordType, lenField, lenReg);
    output.fun.store(voidp, ptrField, ptrReg);
    return output.fun.load(structType, structReg);
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

        return makeArray(output, this.type, length, pointer);
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
        auto arrayType = cast(Array) this.array.type;
        assert(arrayType, "slice of non-array");
        const elementSize = arrayType.elementType.emit(output.platform).size(output.platform);

        auto arrayReg = this.array.emit(output);
        auto lowerReg = this.lower.emit(output);
        auto upperReg = this.upper.emit(output);
        auto ptr = getArrayPtr(output, arrayType, arrayReg);
        // ptr = ptr + lower
        Reg lowerOffset = output.fun.binop(
            "*", output.platform.nativeWordSize,
            lowerReg, output.fun.longLiteral(elementSize));
        Reg newPtr = output.fun.call(voidp, "ptr_offset", [ptr, lowerOffset]);
        // len = upper - lower
        Reg newLen = output.fun.binop(
            "-", output.platform.nativeWordSize,
            upperReg, lowerReg);

        return makeArray(output, arrayType, newLen, newPtr);
    }

    mixin(GenerateThis);
}
