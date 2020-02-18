#pragma once

#include <stdlib.h>
#include <string.h>

#include "instr.h"
#include "type.h"
#include "util.h"

void *alloc(Data *data, size_t size);

size_t begin_declare_section(Data *data);

size_t begin_define_section(Data *data, size_t index);

void end_section(Data *data, size_t start);

void add_type_int(Data *data);

void add_string(Data *data, const char* text);

void add_arg_instr(Data *data, int index);

void start_call_instr(Data *data, int offset, int args);

void add_call_slot_arg(Data *data, int slotid);

void add_call_int_arg(Data *data, int value);

void add_tbr_instr(Data *data, int slot, int blkthen, int blkelse);

void add_ret_instr(Data *data, int slot);

size_t alloc_block_offsets(Data *data, int num_offsets);

void start_block(Data *data, int symbol_base_offset, int *offset_ptr, int slot_types_len);
