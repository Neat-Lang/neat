#pragma once

#include <stdlib.h>
#include <string.h>

#include "instr.h"
#include "type.h"
#include "util.h"

void *alloc(Data *data, size_t size);

size_t begin_declare_section(BytecodeBuilder *builder);

DefineSectionState *begin_define_section(BytecodeBuilder *builder, size_t index);

void end_declare_section(Data *data, size_t start);

void declare_symbol(BytecodeBuilder *builder, int args);

void end_define_section(BytecodeBuilder *builder, DefineSectionState *state);

size_t alloc_offsets(Data *data, int num_offsets);

void add_string(Data *data, const char* text);

void add_type_int(Data *data);

void add_type_pointer(Data *data);

void add_type_struct(Data *data, int members);

size_t start_alloc_instr(DefineSectionState *state);

int end_alloc_instr(DefineSectionState *state, size_t offset);

size_t start_offset_instr(DefineSectionState *state, int reg, size_t index);

int end_offset_instr(DefineSectionState *state, size_t offset);

size_t start_load_instr(DefineSectionState *state, int pointer_reg);

int end_load_instr(DefineSectionState *state, size_t offset);

void add_store_instr(DefineSectionState *state, int value_reg, int pointer_reg);

int add_arg_instr(DefineSectionState *state, int index);

int add_literal_instr(DefineSectionState *state, int value);

int start_call_instr(DefineSectionState *state, int offset, int args);

void add_call_reg_arg(DefineSectionState *state, int reg);

void add_call_int_arg(DefineSectionState *state, int value);

int add_br_instr(DefineSectionState *state);

void br_resolve(DefineSectionState *state, int br_offset, int block);

int add_tbr_instr(DefineSectionState *state, int reg);

void tbr_resolve_then(DefineSectionState *state, int tbr_offset, int block);

void tbr_resolve_else(DefineSectionState *state, int tbr_offset, int block);

void add_ret_instr(DefineSectionState *state, int reg);

int start_block(DefineSectionState *state);
