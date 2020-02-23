#include <assert.h>
#include <fcntl.h>
#include <stdio.h>
#include <unistd.h>

#include "build_bc.h"
#include "symbol.h"

int main(int argc, const char **argv) {
    Data *file_data = alloc_data();

    int int_eq_offset = 0;
    int int_eq_section = begin_declare_section(file_data);
    declare_symbol(file_data, 2);
    add_string(file_data, "int_eq");
    add_type_int(file_data); // ret
    add_type_int(file_data);
    add_type_int(file_data);
    end_declare_section(file_data, int_eq_section);

    int int_add_offset = 1;
    int int_add_section = begin_declare_section(file_data);
    declare_symbol(file_data, 2);
    add_string(file_data, "int_add");
    add_type_int(file_data); // ret
    add_type_int(file_data);
    add_type_int(file_data);
    end_declare_section(file_data, int_add_section);

    int int_sub_offset = 2;
    int int_sub_section = begin_declare_section(file_data);
    declare_symbol(file_data, 2);
    add_string(file_data, "int_sub");
    add_type_int(file_data); // ret
    add_type_int(file_data);
    add_type_int(file_data);
    end_declare_section(file_data, int_sub_section);

    int ack_offset = 3;
    int ack_declare_section = begin_declare_section(file_data);
    declare_symbol(file_data, 2);
    add_string(file_data, "ack");
    add_type_int(file_data); // ret
    add_type_int(file_data);
    add_type_int(file_data);
    end_declare_section(file_data, ack_declare_section);

    DefineSectionState *ack_define_section = begin_define_section(ack_offset);
    int branch1;
    {
        start_block(ack_define_section);
        int arg0 = add_arg_instr(ack_define_section, 0); // %0 = arg(0)

        int call = start_call_instr(ack_define_section, int_eq_offset, 2); // %1 = %0 == 0
        add_call_reg_arg(ack_define_section, arg0);
        add_call_int_arg(ack_define_section, 0);

        branch1 = add_tbr_instr(ack_define_section, call);
    }

    {
        int then1 = start_block(ack_define_section);

        tbr_resolve_then(ack_define_section, branch1, then1);

        int arg1 = add_arg_instr(ack_define_section, 1); // %2 = arg(1)

        int call = start_call_instr(ack_define_section, int_add_offset, arg1); // %3 = %2 + 1
        add_call_reg_arg(ack_define_section, arg1);
        add_call_int_arg(ack_define_section, 1);

        add_ret_instr(ack_define_section, call); // ret %3
    }

    int branch2;
    {
        int else1 = start_block(ack_define_section);

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
    end_define_section(file_data, ack_define_section);

    int bcfile = creat("ack.bc", 0644);
    for (int i = 0; i < file_data->length;)
    {
        int written = write(bcfile, (char*) file_data->ptr + i, file_data->length - i);
        assert(written != -1);
        i += written;
    }
    close(bcfile);
    free_data(file_data);
}
