#pragma once

#include "type.h"
#include "util.h"

typedef struct {
    Type ret;
    int args_len;
    char name[0];
    // and then: arg types
} Symbol;

typedef enum {
    UNRESOLVED_SYMBOL,
    C_SYMBOL,
    BC_SYMBOL,
} SymbolKind;

typedef void (*callptr_t)(int values_len, Value *values_ptr, Value *ret_ptr);

typedef struct {
    SymbolKind kind;
    Symbol *symbol;
    union {
        callptr_t callptr;
        struct {
            Type *arg_types; // cache for offset off symbol
            DefineSection *section;
        };
    };
} SymbolEntry;

typedef struct {
    int length;
    SymbolEntry *ptr;
} SymbolTable;

typedef struct  {
    SymbolTable entries;
} Environment;

int declare(Environment *environment, Symbol *symbol);

SymbolEntry *find_symbol(Environment *environment, const char *name);

void resolve_c(Environment *environment, const char *name, callptr_t callptr);

void resolve_bc(Environment *environment, const char *name, DefineSection *define_section);
