#pragma once

typedef enum {
    INT,
    VOID,
    STRUCT,
    POINTER
} TypeKind;

typedef struct {
    TypeKind kind;
} Type;

typedef struct {
    Type base;
} PointerType; // and then target type

typedef struct {
    Type base;
    int members;
} StructType;

Type *skip_type(Type *type);

int typesz(Type *type);
