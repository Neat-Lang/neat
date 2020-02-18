#include <stdio.h>

#include "build_bc.h"
#include "symbol.h"

int main(int argc, const char **argv) {
    Data file_data = { .ptr = NULL, .length = 0 };

    int int_eq_offset = 0;
    int int_eq_section = begin_declare_section(&file_data);
    Symbol *int_eq = alloc(&file_data, ASIZEOF(Symbol));
    int_eq->ret.kind = INT;
    int_eq->args_len = 2;
    add_string(&file_data, "int_eq");
    add_type_int(&file_data);
    add_type_int(&file_data);
    end_section(&file_data, int_eq_section);

    int int_add_offset = 1;
    int int_add_section = begin_declare_section(&file_data);
    Symbol *int_add = alloc(&file_data, ASIZEOF(Symbol));
    int_add->ret.kind = INT;
    int_add->args_len = 2;
    add_string(&file_data, "int_add");
    add_type_int(&file_data);
    add_type_int(&file_data);
    end_section(&file_data, int_add_section);

    int int_sub_offset = 2;
    int int_sub_section = begin_declare_section(&file_data);
    Symbol *int_sub = alloc(&file_data, ASIZEOF(Symbol));
    int_sub->ret.kind = INT;
    int_sub->args_len = 2;
    add_string(&file_data, "int_sub");
    add_type_int(&file_data);
    add_type_int(&file_data);
    end_section(&file_data, int_sub_section);

    int ack_offset = 3;
    int ack_declare_section = begin_declare_section(&file_data);
    int ack_byte_offset = file_data.length;
    Symbol *ack = alloc(&file_data, ASIZEOF(Symbol));
    ack->ret.kind = INT;
    ack->args_len = 2;
    add_string(&file_data, "ack");
    add_type_int(&file_data);
    add_type_int(&file_data);
    end_section(&file_data, ack_declare_section);

    int ack_define_section = begin_define_section(&file_data, ack_offset);
    int block_offsets_offset = alloc_block_offsets(&file_data, 5);
#define BLOCK_OFFSETS ((int*)((char*) file_data.ptr + block_offsets_offset))
    // block 0
    start_block(&file_data, ack_byte_offset, &BLOCK_OFFSETS[0], 2);
    add_type_int(&file_data);
    add_type_int(&file_data);
    add_arg_instr(&file_data, 0); // 0
    start_call_instr(&file_data, int_eq_offset, 2); // 1
    add_call_slot_arg(&file_data, 0);
    add_call_int_arg(&file_data, 0);
    add_tbr_instr(&file_data, 1, 1, 2);
    // block 1
    start_block(&file_data, ack_byte_offset, &BLOCK_OFFSETS[1], 2);
    add_type_int(&file_data);
    add_type_int(&file_data);
    add_arg_instr(&file_data, 1); // 0
    start_call_instr(&file_data, int_add_offset, 2); // 1
    add_call_slot_arg(&file_data, 0);
    add_call_int_arg(&file_data, 1);
    add_ret_instr(&file_data, 1);
    // block 2
    start_block(&file_data, ack_byte_offset, &BLOCK_OFFSETS[2], 2);
    add_type_int(&file_data);
    add_type_int(&file_data);
    add_arg_instr(&file_data, 1);
    start_call_instr(&file_data, int_eq_offset, 2);
    add_call_slot_arg(&file_data, 0);
    add_call_int_arg(&file_data, 0);
    add_tbr_instr(&file_data, 1, 3, 4);
    // block 3
    start_block(&file_data, ack_byte_offset, &BLOCK_OFFSETS[3], 3);
    for (int i = 0; i < 3; i++) add_type_int(&file_data);
    add_arg_instr(&file_data, 0); // %0 = arg(0)
    start_call_instr(&file_data, int_sub_offset, 2); // %1 = int_sub(%0, 1)
    add_call_slot_arg(&file_data, 0);
    add_call_int_arg(&file_data, 1);
    start_call_instr(&file_data, ack_offset, 2); // %2 = ack(%1, 1)
    add_call_slot_arg(&file_data, 1);
    add_call_int_arg(&file_data, 1);
    add_ret_instr(&file_data, 2);
    // block 4
    start_block(&file_data, ack_byte_offset, &BLOCK_OFFSETS[4], 6);
    for (int i = 0; i < 6; i++) add_type_int(&file_data);
    add_arg_instr(&file_data, 1); // 0
    start_call_instr(&file_data, int_sub_offset, 2); // 1
    add_call_slot_arg(&file_data, 0);
    add_call_int_arg(&file_data, 1);
    add_arg_instr(&file_data, 0); // 2
    start_call_instr(&file_data, ack_offset, 2); // 3
    add_call_slot_arg(&file_data, 2);
    add_call_slot_arg(&file_data, 1);
    start_call_instr(&file_data, int_sub_offset, 2); // 4
    add_call_slot_arg(&file_data, 2);
    add_call_int_arg(&file_data, 1);
    start_call_instr(&file_data, ack_offset, 2); // 5
    add_call_slot_arg(&file_data, 4);
    add_call_slot_arg(&file_data, 3);
    add_ret_instr(&file_data, 5);
#undef BLOCK_OFFSETS
    end_section(&file_data, ack_define_section);

    FILE *bcfile = fopen("ack.bc", "w");
    fwrite(file_data.ptr, 1, file_data.length, bcfile);
    fclose(bcfile);
}
