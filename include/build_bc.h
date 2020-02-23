#pragma once

#include <stdlib.h>
#include <string.h>

#include "instr.h"
#include "type.h"
#include "util.h"

void *alloc(Data *data, size_t size);

size_t begin_declare_section(Data *data);

DefineSectionState *begin_define_section(size_t index);

void end_declare_section(Data *data, size_t start);

void declare_symbol(Data *data, int args);

void end_define_section(Data *data, DefineSectionState *state);

size_t alloc_offsets(Data *data, int num_offsets);

void add_string(Data *data, const char* text);

void add_type_int(Data *data);

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
