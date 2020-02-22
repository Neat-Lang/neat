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
    result.num_registers = 0;
    result.regfile_size = 0;

    DefineSection *define_section = alloc(data, ASIZEOF(DefineSection));
    define_section->base.kind = DEFINE_SECTION;
    define_section->declaration_index = index;

    return result;
}

void end_declare_section(Data *data, size_t start) {
    size_t length = data->length - start;

    Section *section = (Section*)((char*) data->ptr + start);
    section->length = length;
}

void end_define_section(DefineSectionState state) {
    DefineSection *define_section = (DefineSection*)((char*) state.data->ptr + state.start);
    define_section->num_blocks = state.num_blocks;
    define_section->block_offsets_start = state.data->length - state.start;

    BlockData *block_data = alloc(state.data, sizeof(BlockData) * (state.num_blocks + 1));
    for (int i = 0; i < state.num_blocks; i++) {
        block_data[i] = ((BlockData*) state.offsets_data.ptr)[i];
    }
    block_data[state.num_blocks] = (BlockData) {
        .block_offset = 0,
        .register_offset = state.num_registers,
        .regfile_offset = state.regfile_size,
    };

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

int add_arg_instr(DefineSectionState *state, int index) {
    ArgInstr *arg_instr = alloc(state->data, ASIZEOF(ArgInstr));
    arg_instr->base.kind = INSTR_ARG;
    arg_instr->index = index;
    // TODO
    state->regfile_size += 4;
    return state->num_registers++;
}

int start_call_instr(DefineSectionState *state, int offset, int args) {
    CallInstr *call_instr = alloc(state->data, ASIZEOF(CallInstr));
    call_instr->base.kind = INSTR_CALL;
    call_instr->symbol_offset = offset;
    call_instr->args_num = args;
    // TODO void, other types
    state->regfile_size += 4;
    return state->num_registers++;
}

void add_call_reg_arg(DefineSectionState *state, int reg) {
    ArgExpr *arg_expr = alloc(state->data, ASIZEOF(ArgExpr));
    arg_expr->kind = REG_ARG;
    arg_expr->value = reg;
}

void add_call_int_arg(DefineSectionState *state, int value) {
    ArgExpr *arg_expr = alloc(state->data, ASIZEOF(ArgExpr));
    arg_expr->kind = INT_LITERAL_ARG;
    arg_expr->value = value;
}

int add_tbr_instr(DefineSectionState *state, int reg) {
    int offset = state->data->length;
    TestBranchInstr *tbr_instr = alloc(state->data, ASIZEOF(TestBranchInstr));
    tbr_instr->base.kind = INSTR_TESTBRANCH;
    tbr_instr->reg = reg;
    return offset;
}

void tbr_resolve_then(DefineSectionState *state, int offset, int thenblk) {
    TestBranchInstr *tbr_instr = (TestBranchInstr*)(state->data->ptr + offset);
    tbr_instr->then_blk = thenblk;
}

void tbr_resolve_else(DefineSectionState *state, int offset, int elseblk) {
    TestBranchInstr *tbr_instr = (TestBranchInstr*)(state->data->ptr + offset);
    tbr_instr->else_blk = elseblk;
}

void add_ret_instr(DefineSectionState *state, int reg) {
    ReturnInstr *ret_instr = alloc(state->data, ASIZEOF(ReturnInstr));
    ret_instr->base.kind = INSTR_RETURN;
    ret_instr->reg = reg;
}

int start_block(DefineSectionState *state) {
    state->data->length = WORD_ALIGN(state->data->length);

    BlockData *block_data = alloc(&state->offsets_data, sizeof(BlockData));
    block_data->block_offset = state->data->length - state->start;
    block_data->register_offset = state->num_registers;
    block_data->regfile_offset = state->regfile_size;
    return state->num_blocks++;
}
