#pragma once

#include <stdlib.h>

#include "type.h"

#define WORD_ALIGN(I) ((I + 7) & 0xfffffffffffffff8)
#define ASIZEOF(T) WORD_ALIGN(sizeof(T))

typedef struct {
    void *ptr;
    size_t length;
} Data;

typedef enum {
    DECLARE_SECTION,
    DEFINE_SECTION
} SectionKind;

typedef struct {
    SectionKind kind;
    int length; // including Section header
    // and then: data
} Section;

typedef struct {
    Section base;
    int declaration_index;
} DefineSection;

typedef struct {
    int slot_types_len;
    // and then: [slot type: Type], [Instr]
} Block;

typedef struct {
    Type type;
    int int_value;
} Value;
