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
    Value *restrict values_ptr, Value *restrict ret_ptr)
{
    assert(entry->symbol->args_len == values_len);
    assert(entry->kind != UNRESOLVED_SYMBOL);

    if (entry->kind == C_SYMBOL) {
        entry->callptr(values_len, values_ptr, ret_ptr);
        return;
    }
    assert(entry->kind == BC_SYMBOL);

    int num_slots = entry->slots;
    int *block_offsets = (int*) ((char*) entry->block_data + entry->block_offsets_start);

    int blkid = 0; // entry

    // fill in lazily as you walk instructions
    Value values[num_slots];

    while (true) {
restart_block_loop:;
        char *start = ((char*) entry->block_data + block_offsets[blkid]);
        int start_slot = *(int*) start;
        int cur_slot = start_slot;
        BaseInstr *restrict instr = (BaseInstr*) (start + ASIZEOF(int));
        // printf(" blk %i (%p) start %i\n", blkid, (void*) instr, start_slot);
        Value *current_value = &values[start_slot];
        while (true) {
            // printf("  instr %i @%lu\n", instr->kind, (char*) instr - (char*) block_offsets);
            switch (instr->kind) {
                case INSTR_ARG:
                {
                    ArgInstr *arginstr = (ArgInstr*) instr;
                    *current_value = values_ptr[arginstr->index];
                    // printf("    %%%i = arg(%i) = %i\n", cur_slot, arginstr->index, current_value->int_value);
                    instr = (BaseInstr*) ((char*) instr + ASIZEOF(ArgInstr));
                }
                break;
                case INSTR_CALL:
                {
                    CallInstr *callinstr = (CallInstr*) instr;
                    Value call_args[callinstr->args_num];
                    ArgExpr *cur_arg = (ArgExpr*)((char*) callinstr + ASIZEOF(CallInstr));
                    for (int arg_id = 0; arg_id < callinstr->args_num; arg_id++) {
                        switch (cur_arg->kind) {
                            case INT_LITERAL_ARG:
                                // printf("      -literal %i\n", cur_arg->value);
                                call_args[arg_id].type.kind = INT;
                                call_args[arg_id].int_value = cur_arg->value;
                                break;
                            case SLOT_ARG:
                                // printf("      -slot %i\n", cur_arg->value);
                                call_args[arg_id] = values[cur_arg->value];
                                break;
                            default:
                                assert(false);
                        }
                        cur_arg = (ArgExpr*)((char*) cur_arg + ASIZEOF(ArgExpr));;
                    }
                    instr = (BaseInstr*) cur_arg;
                    SymbolEntry *entry = &environment->entries.ptr[callinstr->symbol_offset];
                    // char *symbol_name = (char*) entry->symbol + ASIZEOF(Symbol);
                    // printf("    %%%i = call %s(%i, %i)\n", cur_slot, symbol_name, call_args[0].int_value, call_args[1].int_value);
                    call(environment, entry, callinstr->args_num, call_args, current_value);
                    assert(current_value->type.kind == INT);
                }
                break;
                case INSTR_TESTBRANCH:
                {
                    TestBranchInstr *tbr_instr = (TestBranchInstr*) instr;
                    Value slot = values[tbr_instr->slot];
                    assert(slot.type.kind == INT);
                    blkid = (slot.int_value) ? tbr_instr->then_blk : tbr_instr->else_blk;
                }
                goto restart_block_loop;
                case INSTR_RETURN:
                {
                    ReturnInstr *ret_instr = (ReturnInstr*) instr;
                    Value slot = values[ret_instr->slot];
                    *ret_ptr = slot;
                    return;
                }
                default:
                    fprintf(stderr, "what is instr %i\n", instr->kind);
                    assert(false);
            }
            current_value = (Value*)((char*) current_value + ASIZEOF(Value));
            cur_slot ++;
        }
    }
}

void int_eq_fn(int arg_len, Value *arg_ptr, Value *ret_ptr) {
    assert(arg_len == 2);
    assert(arg_ptr[0].type.kind == INT);
    assert(arg_ptr[1].type.kind == INT);
    ret_ptr->type.kind = INT;
    ret_ptr->int_value = arg_ptr[0].int_value == arg_ptr[1].int_value;
}

void int_add_fn(int arg_len, Value *arg_ptr, Value *ret_ptr) {
    assert(arg_len == 2);
    assert(arg_ptr[0].type.kind == INT);
    assert(arg_ptr[1].type.kind == INT);
    ret_ptr->type.kind = INT;
    ret_ptr->int_value = arg_ptr[0].int_value + arg_ptr[1].int_value;
}

void int_sub_fn(int arg_len, Value *arg_ptr, Value *ret_ptr) {
    assert(arg_len == 2);
    assert(arg_ptr[0].type.kind == INT);
    assert(arg_ptr[1].type.kind == INT);
    ret_ptr->type.kind = INT;
    ret_ptr->int_value = arg_ptr[0].int_value - arg_ptr[1].int_value;
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
            int slots = define_section->slots;
            int block_offsets_start = define_section->block_offsets_start;
            resolve_bc(&environment, symbol->name, (char*) define_section + ASIZEOF(DefineSection), block_offsets_start, slots);
        }
        section = (Section*)((char*) section + section->length);
    }

    resolve_c(&environment, "int_eq", int_eq_fn);
    resolve_c(&environment, "int_add", int_add_fn);
    resolve_c(&environment, "int_sub", int_sub_fn);
    // whew...
#undef BLOCK_OFFSETS
    SymbolEntry *entry = find_symbol(&environment, "ack");
    Value ret;
    Value args[2];
    args[0].type.kind = INT;
    args[0].int_value = 3;
    args[1].type.kind = INT;
    args[1].int_value = 8;
    for (int i = 0; i < 10; i++) {
        call(&environment, entry, 2, args, &ret);
        printf("ack(%i, %i) = %i\n", args[0].int_value, args[1].int_value, ret.int_value);
    }
    return 0;
}
