#include <assert.h>
#include <fcntl.h>
#include <stdio.h>
#include <unistd.h>

#include "build_bc.h"
#include "symbol.h"

int main(int argc, const char **argv) {
    BytecodeBuilder *builder = alloc_bc_builder();

    int int_eq_offset = builder->symbol_offsets_len;
    int int_eq_section = begin_declare_section(builder);
    declare_symbol(builder, 2);
    add_string(builder->data, "int_eq");
    add_type_int(builder->data); // ret
    add_type_int(builder->data);
    add_type_int(builder->data);
    end_declare_section(builder->data, int_eq_section);

    int int_add_offset = builder->symbol_offsets_len;
    int int_add_section = begin_declare_section(builder);
    declare_symbol(builder, 2);
    add_string(builder->data, "int_add");
    add_type_int(builder->data); // ret
    add_type_int(builder->data);
    add_type_int(builder->data);
    end_declare_section(builder->data, int_add_section);

    int int_sub_offset = builder->symbol_offsets_len;
    int int_sub_section = begin_declare_section(builder);
    declare_symbol(builder, 2);
    add_string(builder->data, "int_sub");
    add_type_int(builder->data); // ret
    add_type_int(builder->data);
    add_type_int(builder->data);
    end_declare_section(builder->data, int_sub_section);

    int ack_offset = builder->symbol_offsets_len;
    int ack_declare_section = begin_declare_section(builder);
    declare_symbol(builder, 2);
    add_string(builder->data, "ack");
    add_type_int(builder->data); // ret
    add_type_int(builder->data);
    add_type_int(builder->data);
    end_declare_section(builder->data, ack_declare_section);

    DefineSectionState *ack_define_section = begin_define_section(builder, ack_offset);
    int branch1;
    {
        start_block(ack_define_section);
        // %0 = new { int, int }
        size_t alloc = start_alloc_instr(ack_define_section);
        add_type_struct(ack_define_section->main_data, 2);
        add_type_int(ack_define_section->main_data);
        add_type_int(ack_define_section->main_data);
        int frame = end_alloc_instr(ack_define_section, alloc);

        size_t offset1 = start_offset_instr(ack_define_section, frame, 0);
        add_type_struct(ack_define_section->main_data, 2);
        add_type_int(ack_define_section->main_data);
        add_type_int(ack_define_section->main_data);
        int frame_m = end_offset_instr(ack_define_section, offset1); // %1 = &%0->_0

        size_t offset2 = start_offset_instr(ack_define_section, frame, 1);
        add_type_struct(ack_define_section->main_data, 2);
        add_type_int(ack_define_section->main_data);
        add_type_int(ack_define_section->main_data);
        int frame_n = end_offset_instr(ack_define_section, offset2); // %2 = &%0->_1

        int arg0 = add_arg_instr(ack_define_section, 0); // %3 = arg(0)
        int arg1 = add_arg_instr(ack_define_section, 1); // %4 = arg(1)
        add_store_instr(ack_define_section, arg0, frame_m); // *%1 = %3
        add_type_int(ack_define_section->main_data);
        add_store_instr(ack_define_section, arg1, frame_n); // *%2 = %4
        add_type_int(ack_define_section->main_data);
        int argzero = add_literal_instr(ack_define_section, 0); // %2 = 0

        size_t arg0_load_offset = start_load_instr(ack_define_section, frame_m);
        add_type_int(ack_define_section->main_data);
        int arg0_frame = end_load_instr(ack_define_section, arg0_load_offset);

        int call = start_call_instr(ack_define_section, int_eq_offset, 2); // %3 = m == 0
        // add_call_reg_arg(ack_define_section, arg0); (void) arg0_frame;
        add_call_reg_arg(ack_define_section, arg0_frame);
        add_call_reg_arg(ack_define_section, argzero);

        branch1 = add_tbr_instr(ack_define_section, call); // tbr %3, :1, :2
    }

    {
        int then1 = start_block(ack_define_section);

        tbr_resolve_then(ack_define_section, branch1, then1);

        int arg1 = add_arg_instr(ack_define_section, 1); // %2 = arg(1)

        int call = start_call_instr(ack_define_section, int_add_offset, 2); // %3 = %2 + 1
        add_call_reg_arg(ack_define_section, arg1);
        add_call_int_arg(ack_define_section, 1);

        add_ret_instr(ack_define_section, call); // ret %3
    }

    int empty_else;
    {
        start_block(ack_define_section);

        empty_else = add_br_instr(ack_define_section);
    }

    int branch2;
    {
        int else1 = start_block(ack_define_section);

        br_resolve(ack_define_section, empty_else, else1);
        tbr_resolve_else(ack_define_section, branch1, else1);

        int arg1 = add_arg_instr(ack_define_section, 1); // %4 = arg(1)

        int call = start_call_instr(ack_define_section, int_eq_offset, 2); // %5 = %4 == 0
        add_call_reg_arg(ack_define_section, arg1);
        add_call_int_arg(ack_define_section, 0);

        branch2 = add_tbr_instr(ack_define_section, call);
    }

    {
        int then2 = start_block(ack_define_section);

        tbr_resolve_then(ack_define_section, branch2, then2);

        int arg0 = add_arg_instr(ack_define_section, 0); // %6 = arg(0)

        int call1 = start_call_instr(ack_define_section, int_sub_offset, 2); // %7 = %6 - 1
        add_call_reg_arg(ack_define_section, arg0);
        add_call_int_arg(ack_define_section, 1);

        int call2 = start_call_instr(ack_define_section, ack_offset, 2); // %8 = ack(%7, 1)
        add_call_reg_arg(ack_define_section, call1);
        add_call_int_arg(ack_define_section, 1);

        add_ret_instr(ack_define_section, call2);
    }

    {
        int else2 = start_block(ack_define_section);

        tbr_resolve_else(ack_define_section, branch2, else2);

        int arg1 = add_arg_instr(ack_define_section, 1); // %9 = arg(1)

        int call1 = start_call_instr(ack_define_section, int_sub_offset, 2); // %10 = %9 - 1
        add_call_reg_arg(ack_define_section, arg1);
        add_call_int_arg(ack_define_section, 1);

        int arg0 = add_arg_instr(ack_define_section, 0); // %11 = arg(0)

        int call2 = start_call_instr(ack_define_section, ack_offset, 2); // %12 = ack(%11, %10)
        add_call_reg_arg(ack_define_section, arg0);
        add_call_reg_arg(ack_define_section, call1);

        int call3 = start_call_instr(ack_define_section, int_sub_offset, 2); // %13 = %11 - 1
        add_call_reg_arg(ack_define_section, arg0);
        add_call_int_arg(ack_define_section, 1);

        int call4 = start_call_instr(ack_define_section, ack_offset, 2); // %14 = ack(%13, %12)
        add_call_reg_arg(ack_define_section, call3);
        add_call_reg_arg(ack_define_section, call2);

        add_ret_instr(ack_define_section, call4); // ret %14
    }
    end_define_section(builder, ack_define_section);

    int bcfile = creat("ack.bc", 0644);
    for (int i = 0; i < builder->data->length;)
    {
        int written = write(bcfile, (char*) builder->data->ptr + i, builder->data->length - i);
        assert(written != -1);
        i += written;
    }
    close(bcfile);
    free_bc_builder(builder);
}
