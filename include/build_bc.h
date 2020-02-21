#pragma once

#include <stdlib.h>
#include <string.h>

#include "instr.h"
#include "type.h"
#include "util.h"

void *alloc(Data *data, size_t size);

size_t begin_declare_section(Data *data);

DefineSectionState begin_define_section(Data *data, size_t index);

void end_declare_section(Data *data, size_t start);

void end_define_section(DefineSectionState state);

size_t alloc_offsets(Data *data, int num_offsets);

void add_string(Data *data, const char* text);

void add_type_int(Data *data);

int add_arg_instr(DefineSectionState *state, int index);

int start_call_instr(DefineSectionState *state, int offset, int args);

void add_call_slot_arg(DefineSectionState *state, int slotid);

void add_call_int_arg(DefineSectionState *state, int value);

void add_tbr_instr(DefineSectionState *state, int slot, int blkthen, int blkelse);

void add_ret_instr(DefineSectionState *state, int slot);

void start_block(DefineSectionState *state, int symbol_base_offset);
