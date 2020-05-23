module array;

import backend.backend;
import base;
import boilerplate;
import std.format : format;
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
