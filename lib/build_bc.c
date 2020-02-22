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
    result.num_blocks = 0;

    DefineSection *define_section = alloc(data, ASIZEOF(DefineSection));
    define_section->base.kind = DEFINE_SECTION;
    define_section->declaration_index = index;
    define_section->slots = 0;

    return result;
}

void end_declare_section(Data *data, size_t start) {
    size_t length = data->length - start;

    Section *section = (Section*)((char*) data->ptr + start);
    section->length = length;
}

void end_define_section(DefineSectionState state) {
    DefineSection *define_section = (DefineSection*)((char*) state.data->ptr + state.start);
    define_section->block_offsets_start = state.data->length - (state.start + ASIZEOF(DefineSection));

    int *block_offsets = alloc(state.data, sizeof(int) * state.num_blocks);
    for (int i = 0; i < state.num_blocks; i++) {
        block_offsets[i] = ((int*) state.offsets_data.ptr)[i];
    }

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

static int increment_slot(DefineSectionState *state) {
    DefineSection *define_section = (DefineSection*)((char*) state->data->ptr + state->start);

    return define_section->slots++;
}

int add_arg_instr(DefineSectionState *state, int index) {
    ArgInstr *arg_instr = alloc(state->data, ASIZEOF(ArgInstr));
    arg_instr->base.kind = INSTR_ARG;
    arg_instr->index = index;
    return increment_slot(state);
}

int start_call_instr(DefineSectionState *state, int offset, int args) {
    CallInstr *call_instr = alloc(state->data, ASIZEOF(CallInstr));
    call_instr->base.kind = INSTR_CALL;
    call_instr->symbol_offset = offset;
    call_instr->args_num = args;
    return increment_slot(state);
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

void start_block(DefineSectionState *state) {
    DefineSection *define_section = (DefineSection*)((char*) state->data->ptr + state->start);
    state->data->length = WORD_ALIGN(state->data->length);

    int *block_offset_ptr = alloc(&state->offsets_data, sizeof(int));
    *block_offset_ptr = state->data->length - (state->start + ASIZEOF(DefineSection));
    state->num_blocks++;

    int *start_slot = (int*) alloc(state->data, ASIZEOF(int));

    *start_slot = define_section->slots;
}
