#include "build_bc.h"

void *alloc(Data *data, size_t size) {
    size_t prev_length = data->length;
    data->length += size;
    data->ptr = realloc(data->ptr, data->length);
    return (char*) data->ptr + prev_length;
}

size_t begin_declare_section(Data *data) {
    size_t start = data->length;
    Section *section = alloc(data, ASIZEOF(Section));
    section->kind = DECLARE_SECTION;
    return start;
}

DefineSectionState begin_define_section(Data *data, size_t index) {
    DefineSectionState result;

    result.start = data->length;
    result.data = data;

    DefineSection *define_section = alloc(data, ASIZEOF(DefineSection));
    define_section->base.kind = DEFINE_SECTION;
    define_section->declaration_index = index;
    define_section->slots = 0;

    result.blocks_start = data->length;

    return result;
}

void end_declare_section(Data *data, size_t start) {
    size_t length = data->length - start;

    Section *section = (Section*)((char*) data->ptr + start);
    section->length = length;
}

void end_define_section(DefineSectionState state) {
    end_declare_section(state.data, state.start);
}

void add_type_int(Data *data) {
    Type *type = alloc(data, ASIZEOF(Type));
    type->kind = INT;
}

void add_string(Data *data, const char* text) {
    char *target = alloc(data, WORD_ALIGN(strlen(text) + 1));
    strcpy(target, text);
}

void add_arg_instr(DefineSectionState *state, int index) {
    ArgInstr *arg_instr = alloc(state->data, ASIZEOF(ArgInstr));
    arg_instr->base.kind = INSTR_ARG;
    arg_instr->index = index;
}

void start_call_instr(DefineSectionState *state, int offset, int args) {
    CallInstr *call_instr = alloc(state->data, ASIZEOF(CallInstr));
    call_instr->base.kind = INSTR_CALL;
    call_instr->symbol_offset = offset;
    call_instr->args_num = args;
}

void add_call_slot_arg(DefineSectionState *state, int slotid) {
    ArgExpr *arg_expr = alloc(state->data, ASIZEOF(ArgExpr));
    arg_expr->kind = SLOT_ARG;
    arg_expr->value = slotid;
}

void add_call_int_arg(DefineSectionState *state, int value) {
    ArgExpr *arg_expr = alloc(state->data, ASIZEOF(ArgExpr));
    arg_expr->kind = INT_LITERAL_ARG;
    arg_expr->value = value;
}

void add_tbr_instr(DefineSectionState *state, int slot, int blkthen, int blkelse) {
    TestBranchInstr *tbr_instr = alloc(state->data, ASIZEOF(TestBranchInstr));
    tbr_instr->base.kind = INSTR_TESTBRANCH;
    tbr_instr->slot = slot;
    tbr_instr->then_blk = blkthen;
    tbr_instr->else_blk = blkelse;
}

void add_ret_instr(DefineSectionState *state, int slot) {
    ReturnInstr *ret_instr = alloc(state->data, ASIZEOF(ReturnInstr));
    ret_instr->base.kind = INSTR_RETURN;
    ret_instr->slot = slot;
}

size_t alloc_offsets(Data *data, int num_offsets) {
    size_t offset = data->length;
    alloc(data, sizeof(int) * num_offsets);
    return offset;
}

void start_block(DefineSectionState *state, int symbol_base_offset, int *block_offset_ptr, int slots) {
    DefineSection *define_section = (DefineSection*)((char*) state->data->ptr + state->start);
    int defined_slots = define_section->slots;

    define_section->slots += slots; // TODO increment in add_instrs

    state->data->length = WORD_ALIGN(state->data->length);

    *block_offset_ptr = state->data->length - state->blocks_start;

    int *start_slot = (int*) alloc(state->data, ASIZEOF(int));

    *start_slot = defined_slots;
}
