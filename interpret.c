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

    int *restrict block_offsets = (int*) entry->block_data;
    int blkid = 0; // entry

    while (true) {
        Block *restrict blk = (Block*)((char*) entry->symbol + block_offsets[blkid]);
        // printf(" blk %i (%i) %p\n", blkid, blk->slot_types_len, (void*) blk);
        Type *restrict type_cur = (Type*)((char*) blk + ASIZEOF(Block));
        for (int i = 0; i < blk->slot_types_len; i++) {
            type_cur = (Type*)((char*) type_cur + ASIZEOF(Type)); // TODO handle types with dynamic size
        }
        // fill in lazily as you walk instructions
        Value values[blk->slot_types_len];
        BaseInstr *restrict instr = (BaseInstr*) type_cur; // instrs start after types
        Value *current_value = values;
        for (int instr_id = 0; instr_id < blk->slot_types_len; instr_id++) {
            // printf("  instr %i = %i %p\n", instr_id, instr->kind, (void*) instr);
            switch (instr->kind) {
                case INSTR_ARG:
                {
                    ArgInstr *arginstr = (ArgInstr*) instr;
                    *current_value = values_ptr[arginstr->index];
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
                                call_args[arg_id].type.kind = INT;
                                call_args[arg_id].int_value = cur_arg->value;
                                break;
                            case SLOT_ARG:
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
                    // printf("    call %s(%i, %i)\n", symbol_name, call_args[0].int_value, call_args[1].int_value);
                    call(environment, entry, callinstr->args_num, call_args, current_value);
                    assert(current_value->type.kind == INT);
                }
                break;
                default:
                    assert(false);
            }
            current_value = (Value*)((char*) current_value + ASIZEOF(Value));
        }
        // printf("  ~instr %i\n", instr->kind);
        switch (instr->kind) {
            case INSTR_TESTBRANCH:
            {
                TestBranchInstr *tbr_instr = (TestBranchInstr*) instr;
                Value slot = values[tbr_instr->slot];
                assert(slot.type.kind == INT);
                blkid = (slot.int_value) ? tbr_instr->then_blk : tbr_instr->else_blk;
            }
            break;
            case INSTR_RETURN:
            {
                ReturnInstr *ret_instr = (ReturnInstr*) instr;
                Value slot = values[ret_instr->slot];
                *ret_ptr = slot;
                return;
            }
            break;
            default:
                fprintf(stderr, "what is instr %i\n", instr->kind);
                assert(false);
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
            resolve_bc(&environment, symbol->name, (char*) define_section + ASIZEOF(DefineSection));
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
