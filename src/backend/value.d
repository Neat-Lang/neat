module backend.value;

import boilerplate;
import std.format;

struct Value
{
    enum Kind
    {
        Int,
        Void,
        Struct,
        Pointer,
    }
    Kind kind;
    union
    {
        int int_value;
        Value[] fields;
        PointerValue pointer_;
    }

    int as(T : int)()
    in (this.kind == Kind.Int)
    {
        return int_value;
    }

    PointerValue asPointer()
    in (this.kind == Kind.Pointer)
    {
        return this.pointer_;
    }

    ref Value accessField(int field)
    in (this.kind == Kind.Struct)
    {
        return this.fields[field];
    }

    static Value make(T : int)(int i)
    {
        auto ret = Value(Kind.Int);

        ret.int_value = i;
        return ret;
    }

    static Value make(T : void)()
    {
        return Value(Kind.Void);
    }

    static Value makeStruct(Value[] values)
    {
        auto ret = Value(Kind.Struct);

        ret.fields = values.dup;
        return ret;
    }

    static Value makePointer(PointerValue pointer)
    {
        auto ret = Value(Kind.Pointer);

        ret.pointer_ = pointer;
        return ret;
    }

    void checkSameType(Value other)
    {
        if (this.kind == Kind.Int && other.kind == Kind.Int)
        {
            return;
        }
        assert(false, "TODO");
    }

    string toString() const
    {
        final switch (this.kind)
        {
            case Kind.Int:
                return format!"%si"(this.int_value);
            case Kind.Void:
                return "void";
            case Kind.Pointer:
                return format!"&%s"(this.pointer_);
            case Kind.Struct:
                return format!"{%(%s, %)}"(this.fields);
        }
    }
}

/**
 * This type defines a region of addressable values.
 * It is used for the alloca region of stackframes, and the heap.
 */
class MemoryRegion
{
    Value[] values;

    Value allocate(Value value)
    {
        this.values ~= value;

        return Value.makePointer(PointerValue(this, [cast(int) this.values.length - 1]));
    }

    mixin(GenerateToString);
}

struct PointerValue
{
    private MemoryRegion base;

    // the value of the pointer is found by reading the value accessPath[0],
    // then following struct fields at each offset in turn.
    private int[] accessPath;

    invariant (accessPath.length >= 1);

    public Value load()
    {
        return refValue;
    }

    public void store(Value value)
    {
        refValue.checkSameType(value);
        refValue = value;
    }

    public Value offset(int member)
    in (refValue.kind == Value.Kind.Struct && member < refValue.fields.length,
        format("tried to take invalid offset %s of %s from %s", member, refValue, this))
    {
        return Value.makePointer(PointerValue(base, accessPath ~ member));
    }

    private ref Value refValue()
    {
        Value* current_value = &this.base.values[this.accessPath[0]];

        foreach (index; this.accessPath[1 .. $])
        {
            assert(current_value.kind == Value.Kind.Struct);

            current_value = &current_value.accessField(index);
        }
        return *current_value;
    }

    mixin(GenerateThis);
}
