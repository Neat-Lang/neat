#pragma once

typedef enum {
    INT,
    VOID
} TypeKind;

typedef struct {
    TypeKind kind;
} Type;
