module array;

import boilerplate;
import backend.backend;
import base;
import types;

class ASTArray : ASTType
{
    ASTType elementType;

    override Type compile(Namespace namespace)
    {
        return new Array(this.elementType.compile(namespace));
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

    mixin(GenerateThis);
}
