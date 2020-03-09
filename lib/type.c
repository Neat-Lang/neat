#include <assert.h>
#include <stdio.h>

#include "type.h"
#include "util.h"

Type *skip_type(Type *type) {
    if (type->kind == INT || type->kind == VOID) {
        return (Type*)((char*) type + ASIZEOF(Type));
    }
    if (type->kind == STRUCT) {
        StructType *strct_type = (StructType*) type;
        type = (Type*)((char*) strct_type + ASIZEOF(StructType));
        for (int i = 0; i < strct_type->members; i++) {
            type = skip_type(type);
        }
        return type;
    }
    fprintf(stderr, "skip_type: what is type %i\n", type->kind);
    assert(0);
}

int typesz(Type *type) {
    if (type->kind == INT) {
        return 4;
    }
    if (type->kind == VOID) {
        return 0;
    }
    if (type->kind == STRUCT) {
        StructType *strct_type = (StructType*) type;
        type = (Type*)(strct_type + 1);
        int res = 0;
        for (int i = 0; i < strct_type->members; i++) {
            // TODO alignment
            res += typesz(type);
            type = skip_type(type);
        }
        return res;
    }
    fprintf(stderr, "typesz: what is type %i\n", type->kind);
    assert(0);
}
