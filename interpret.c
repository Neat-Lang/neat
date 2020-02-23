#include <alloca.h>
#include <assert.h>
#include <errno.h>
#include <fcntl.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/stat.h>

#include "instr.h"
#include "symbol.h"
#include "util.h"

void call(
    Environment *environment, SymbolEntry *entry, int values_len,
    void **restrict values_ptr, void *restrict ret_ptr)
{
    assert(entry->symbol->args_len == values_len);
    assert(entry->kind != UNRESOLVED_SYMBOL);

    if (entry->kind == C_SYMBOL) {
        entry->callptr(values_len, values_ptr, ret_ptr);
        return;
    }
    assert(entry->kind == BC_SYMBOL);

    int num_blocks = entry->section->num_blocks;
    BlockData *metadata = (BlockData*) ((char*) entry->section + entry->section->block_offsets_start);
    int num_registers = metadata[num_blocks].register_offset;
    int blkid = 0; // entry

    // fill in lazily as you walk instructions
    char *regfile = alloca(metadata[num_blocks].regfile_offset);
    void *values[num_registers];

restart_block_loop:;
    int start_register = metadata[blkid].register_offset;
    char *cur_regfile = (char*) regfile + metadata[blkid].regfile_offset;
    BaseInstr *restrict instr = (BaseInstr*) ((char*) entry->section + metadata[blkid].block_offset);
    /*printf(" blk %i (%p) offset %i start %i regfile %i\n",
            blkid, (void*) instr, metadata[blkid].block_offset, start_register, metadata[blkid].regfile_offset);*/
    void **current_value = &values[start_register];
    while (true) {
        /*printf("  instr %i @%lu sp %p - %p\n",
                instr->kind, (char*) instr - (char*) entry->section, cur_regfile, regfile);*/
        switch (instr->kind) {
            case INSTR_ARG:
            {
                ArgInstr *arginstr = (ArgInstr*) instr;
                // TODO copy into regfile?
                *current_value = values_ptr[arginstr->index];
                // printf("    %%%i = arg(%i) = %i\n", cur_slot, arginstr->index, current_value->int_value);
                instr = (BaseInstr*) ((char*) instr + ASIZEOF(ArgInstr));
            }
            break;
            case INSTR_LITERAL:
            {
                LiteralInstr *litinstr = (LiteralInstr*) instr;
                *(int*) cur_regfile = litinstr->value;
                *current_value = cur_regfile;
                cur_regfile = (char*) cur_regfile + sizeof(int);
                instr = (BaseInstr*) ((char*) instr + ASIZEOF(LiteralInstr));
            }
            break;
            case INSTR_CALL:
            {
                CallInstr *callinstr = (CallInstr*) instr;
                void *call_args[callinstr->args_num];
                ArgExpr *cur_arg = (ArgExpr*)((char*) callinstr + ASIZEOF(CallInstr));
                for (int arg_id = 0; arg_id < callinstr->args_num; arg_id++) {
                    switch (cur_arg->kind) {
                        case INT_LITERAL_ARG:
                            // printf("      -literal %i\n", cur_arg->value);
                            call_args[arg_id] = (void*) &cur_arg->value;
                            break;
                        case REG_ARG:
                            // printf("      -register %i\n", cur_arg->value);
                            call_args[arg_id] = values[cur_arg->value];
                            break;
                        default:
                            printf("      -?? %i\n", cur_arg->kind);
                            assert(false);
                    }
                    cur_arg = (ArgExpr*)((char*) cur_arg + ASIZEOF(ArgExpr));
                }
                instr = (BaseInstr*) cur_arg;
                SymbolEntry *callee = &environment->entries.ptr[callinstr->symbol_offset];
                *current_value = cur_regfile;
                cur_regfile = (char*) cur_regfile + sizeof(int); // TODO
                // char *symbol_name = (char*) callee->symbol + sizeof(Symbol);
                // printf("    %p = call %s(%i, %i)\n", *current_value, symbol_name, *(int*)call_args[0], *(int*)call_args[1]);
                call(environment, callee, callinstr->args_num, call_args, *current_value);
                // printf("     => %i\n", **(int**) current_value);
            }
            break;
            case INSTR_TESTBRANCH:
            {
                TestBranchInstr *tbr_instr = (TestBranchInstr*) instr;
                int regvalue = *(int*) values[tbr_instr->reg];
                blkid = regvalue ? tbr_instr->then_blk : tbr_instr->else_blk;
            }
            goto restart_block_loop;
            case INSTR_RETURN:
            {
                ReturnInstr *ret_instr = (ReturnInstr*) instr;
                // TODO memcpy
                *(int*) ret_ptr = *(int*) values[ret_instr->reg];
                return;
            }
            default:
                fprintf(stderr, "what is instr %i\n", instr->kind);
                assert(false);
        }
        current_value++;
    }
}

void int_eq_fn(int arg_len, void **arg_ptr, void *ret_ptr) {
    assert(arg_len == 2);
    *(int*) ret_ptr = *(int*) arg_ptr[0] == *(int*) arg_ptr[1];
}

void int_add_fn(int arg_len, void **arg_ptr, void *ret_ptr) {
    assert(arg_len == 2);
    *(int*) ret_ptr = *(int*) arg_ptr[0] + *(int*) arg_ptr[1];
}

void int_sub_fn(int arg_len, void **arg_ptr, void *ret_ptr) {
    assert(arg_len == 2);
    *(int*) ret_ptr = *(int*) arg_ptr[0] - *(int*) arg_ptr[1];
}

int main(int argc, const char **argv) {
    int fd = open("ack.bc", O_RDONLY);
    struct stat st;
    fstat(fd, &st);
    void *ack_bc_data = mmap(NULL, st.st_size, PROT_READ, MAP_SHARED, fd, 0);
    if ((size_t) ack_bc_data == -1) {
        fprintf(stderr, "mmap failed: %s\n", strerror(errno));
        abort();
    }

    Environment environment = { 0 };

    Section *section = ack_bc_data;
    Section *file_end = (Section*)((char*) section + st.st_size);
    while (section != file_end) {
        if (section->kind == DECLARE_SECTION) {
            Symbol *symbol = (Symbol*)((char*) section + ASIZEOF(Section));
            declare(&environment, symbol);
        }
        else if (section->kind == DEFINE_SECTION) {
            DefineSection *define_section = (DefineSection*) section;
            Symbol *symbol = environment.entries.ptr[define_section->declaration_index].symbol;
            resolve_bc(&environment, symbol->name, define_section);
        }
        section = (Section*)((char*) section + section->length);
    }

    resolve_c(&environment, "int_eq", int_eq_fn);
    resolve_c(&environment, "int_add", int_add_fn);
    resolve_c(&environment, "int_sub", int_sub_fn);
    // whew...
#undef BLOCK_OFFSETS
    SymbolEntry *entry = find_symbol(&environment, "ack");
    int ret;
    int argvalues[2];
    argvalues[0] = 3;
    argvalues[1] = 8;
    void *args[] = { &argvalues[0], &argvalues[1] };
    for (int i = 0; i < 10; i++) {
        call(&environment, entry, 2, args, &ret);
        printf("ack(%i, %i) = %i\n", argvalues[0], argvalues[1], ret);
    }
    return 0;
}
