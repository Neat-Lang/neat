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
        void[] structData;
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

    static Value makeStruct(void[] structData)
    {
        auto ret = Value(Kind.Struct);

        ret.structData = structData;
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

    void[] data() return
    {
        final switch (this.kind)
        {
            case Kind.Int:
                return cast(void[]) (&this.int_value)[0 .. 1];
            case Kind.Void:
                return null;
            case Kind.Pointer:
                return cast(void[]) (&this.pointer_)[0 .. 1];
            case Kind.Struct:
                return this.structData;
        }
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
                // TODO?
                return format!"{%(%s, %)}"(cast(ubyte[]) this.structData);
        }
    }
}

/**
 * This type defines a region of addressable values.
 * It is used for the alloca region of stackframes, and the heap.
 */
class MemoryRegion
{
    void[] data;

    Value allocate(Value value)
    {
        auto offset = this.data.length;
        auto valueData = value.data;

        this.data ~= valueData;
        return Value.makePointer(PointerValue(this, value.kind, offset, valueData.length));
    }

    mixin(GenerateToString);
}

struct PointerValue
{
    private MemoryRegion base;

    private Value.Kind kind;

    private size_t offset;

    private size_t length;

    public Value load()
    {
        with (Value.Kind) final switch (kind)
        {
            case Int:
                return Value.make!int(*cast(int*) (base.data.ptr + offset));
            case Void:
                return Value.make!void;
            case Pointer:
                return Value.makePointer(*cast(PointerValue*) (base.data.ptr + offset));
            case Struct:
                return Value.makeStruct(base.data.ptr[this.offset .. this.offset + this.length]);
        }
    }

    public void store(Value value)
    {
        assert(value.kind == this.kind, format!"can't store %s in ptr to %s"(value.kind, this.kind));

        with (Value.Kind) final switch (value.kind)
        {
            case Int:
                *cast(int*) (base.data.ptr + offset) = value.as!int;
                break;
            case Void:
                break;
            case Pointer:
                *cast(PointerValue*) (base.data.ptr + offset) = value.asPointer;
                break;
            case Struct:
                assert(this.length == value.structData.length);

                base.data.ptr[this.offset .. this.offset + this.length] = value.data;
                break;
        }
    }

    public Value atOffset(size_t offset, Value.Kind kind)
    {
        return Value.makePointer(PointerValue(base, kind, this.offset + offset, this.length));
    }

    mixin(GenerateThis);
}
