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
    int num_blocks;
    int block_offsets_start; // offset to start of block offset field
} DefineSection;

typedef struct {
    Data *data; // main file (where the types will be written)
    Data offsets_data; // [BlockData] + 1 for full size
    int start; // start of this section in the file
    int num_blocks; // number of blocks
    int num_registers; // number of registers used by the currently building section.
    int regfile_size; // data currently used for registers, in bytes.
} DefineSectionState;

// TODO offset from start of symbol?
typedef struct {
    int block_offset; // offset of this block from start of section
    int register_offset; // index of first register
    int regfile_offset; // offset of first value from base of register file
} BlockData;

typedef struct {
    Type type;
    int int_value;
} Value;
