#include "build_bc.h"

#include <assert.h>

#include "symbol.h"

void *alloc(Data *data, size_t size) {
    size_t prev_length = data->length;
    data->length += size;
    data->ptr = realloc(data->ptr, data->length);
    memset((char*) data->ptr + (data->length - size), 0, size);
    return (char*) data->ptr + prev_length;
}

size_t begin_declare_section(BytecodeBuilder *builder) {
    builder->symbol_offsets_ptr = realloc(
        builder->symbol_offsets_ptr, (++builder->symbol_offsets_len) * sizeof(size_t));
    size_t start = builder->data->length;
    Section *section = alloc(builder->data, ASIZEOF(Section));
    // symbol starts after section header
    builder->symbol_offsets_ptr[builder->symbol_offsets_len - 1] = builder->data->length;
    section->kind = DECLARE_SECTION;
    return start;
}

DefineSectionState* begin_define_section(BytecodeBuilder *builder, size_t index) {
    DefineSectionState *result = calloc(1, sizeof(DefineSectionState));

    result->main_data = alloc_data();
    result->offsets_data = alloc_data();
    result->file_builder = builder;
    result->num_blocks = 0;
    result->num_registers = 0;
    result->regfile_size = 0;

    DefineSection *define_section = alloc(result->main_data, ASIZEOF(DefineSection));
    define_section->base.kind = DEFINE_SECTION;
    define_section->declaration_index = index;

    return result;
}

void end_declare_section(Data *data, size_t start) {
    size_t length = data->length - start;

    Section *section = (Section*)((char*) data->ptr + start);
    section->length = length;
}

void declare_symbol(BytecodeBuilder *builder, int args)
{
    Symbol *sym = alloc(builder->data, sizeof(Symbol));
    sym->args_len = 2;
}

void end_define_section(BytecodeBuilder *builder, DefineSectionState *state) {
    DefineSection *define_section = (DefineSection*) state->main_data->ptr;
    define_section->num_blocks = state->num_blocks;
    define_section->block_offsets_start = state->main_data->length;

    BlockData *block_data = alloc(state->main_data, sizeof(BlockData) * (state->num_blocks + 1));
    for (int i = 0; i < state->num_blocks; i++) {
        block_data[i] = ((BlockData*) state->offsets_data->ptr)[i];
    }
    free_data(state->offsets_data);

    block_data[state->num_blocks] = (BlockData) {
        .block_offset = 0,
        .register_offset = state->num_registers,
        .regfile_offset = state->regfile_size,
    };

    end_declare_section(state->main_data, 0);
    void *target = alloc(builder->data, state->main_data->length);
    memcpy(target, state->main_data->ptr, state->main_data->length);
    free_data(state->main_data);
    free(state);
}

void add_type_int(Data *data) {
    Type *type = alloc(data, ASIZEOF(Type));
    type->kind = INT;
}

void add_type_struct(Data *data, int members) {
    StructType *type = alloc(data, ASIZEOF(StructType));
    type->base.kind = STRUCT;
    type->members = members;
}

void add_type_pointer(Data *data) {
    PointerType *type = alloc(data, ASIZEOF(PointerType));
    type->base.kind = POINTER;
}

void add_string(Data *data, const char* text) {
    char *target = alloc(data, WORD_ALIGN(strlen(text) + 1));
    strcpy(target, text);
}

int add_arg_instr(DefineSectionState *state, int index) {
    DefineSection *define_section = (DefineSection*) state->main_data->ptr;
    size_t own_offset = state->file_builder->symbol_offsets_ptr[define_section->declaration_index];
    Symbol *own_symbol = (Symbol*)((char*) state->file_builder->data->ptr + own_offset);
    ArgInstr *arg_instr = alloc(state->main_data, ASIZEOF(ArgInstr));
    arg_instr->base.kind = INSTR_ARG;
    arg_instr->index = index;
    state->regfile_size += typesz(get_ret_ptr(own_symbol));
    return state->num_registers++;
}

size_t start_alloc_instr(DefineSectionState *state) {
    size_t offset = state->main_data->length;
    AllocInstr *alloc_instr = alloc(state->main_data, ASIZEOF(AllocInstr));
    alloc_instr->base.kind = INSTR_ALLOC;
    return offset;
}

int end_alloc_instr(DefineSectionState *state, size_t offset) {
    AllocInstr *alloc_instr = (AllocInstr*) ((char*) state->main_data->ptr + offset);
    Type *type = (Type*)((char*) alloc_instr + ASIZEOF(AllocInstr));
    state->regfile_size += sizeof(void*) + typesz(type);
    return state->num_registers++;
}

size_t start_offset_instr(DefineSectionState *state, int reg, size_t index) {
    size_t offset = state->main_data->length;
    OffsetAddressInstr *offset_instr = alloc(state->main_data, ASIZEOF(OffsetAddressInstr));
    offset_instr->base.kind = INSTR_OFFSET_ADDRESS;
    offset_instr->reg = reg;
    offset_instr->index = index;
    return offset;
}

int end_offset_instr(DefineSectionState *state, size_t offset) {
    OffsetAddressInstr *offset_instr = (OffsetAddressInstr*) ((char*) state->main_data->ptr + offset);
    Type *type = (Type*)((char*) offset_instr + ASIZEOF(OffsetAddressInstr));
    assert(type->kind == STRUCT);
    type = (Type*)((char*) type + ASIZEOF(Type)); // first member type
    for (int i = 0; i < offset_instr->index; i++) {
        type = skip_type(type);
    }
    // member type n
    state->regfile_size += typesz(type);
    return state->num_registers++;
}

size_t start_load_instr(DefineSectionState *state, int pointer_reg) {
    size_t offset = state->main_data->length;
    LoadInstr *load_instr = alloc(state->main_data, ASIZEOF(LoadInstr));
    load_instr->base.kind = INSTR_LOAD;
    load_instr->pointer_reg = pointer_reg;
    return offset;
}

int end_load_instr(DefineSectionState *state, size_t offset) {
    LoadInstr *load_instr = (LoadInstr*) ((char*) state->main_data->ptr + offset);
    Type *type = (Type*)((char*) load_instr + ASIZEOF(LoadInstr));
    state->regfile_size += typesz(type);
    return state->num_registers++;
}

void add_store_instr(DefineSectionState *state, int value_reg, int pointer_reg) {
    StoreInstr *store_instr = alloc(state->main_data, ASIZEOF(StoreInstr));
    store_instr->base.kind = INSTR_STORE;
    store_instr->value_reg = value_reg;
    store_instr->pointer_reg = pointer_reg;
    state->num_registers++; // void
}

int add_literal_instr(DefineSectionState *state, int value) {
    LiteralInstr *lit_instr = alloc(state->main_data, ASIZEOF(LiteralInstr));
    lit_instr->base.kind = INSTR_LITERAL;
    lit_instr->value = value;
    // TODO
    state->regfile_size += 4;
    return state->num_registers++;
}

int start_call_instr(DefineSectionState *state, int offset, int args) {
    size_t target_offset = state->file_builder->symbol_offsets_ptr[offset];
    Symbol *target = (Symbol*)((char*) state->file_builder->data->ptr + target_offset);
    CallInstr *call_instr = alloc(state->main_data, ASIZEOF(CallInstr));
    call_instr->base.kind = INSTR_CALL;
    call_instr->symbol_offset = offset;
    call_instr->args_num = args;
    state->regfile_size += typesz(get_ret_ptr(target));
    return state->num_registers++;
}

void add_call_reg_arg(DefineSectionState *state, int reg) {
    ArgExpr *arg_expr = alloc(state->main_data, ASIZEOF(ArgExpr));
    arg_expr->kind = REG_ARG;
    arg_expr->value = reg;
}

void add_call_int_arg(DefineSectionState *state, int value) {
    ArgExpr *arg_expr = alloc(state->main_data, ASIZEOF(ArgExpr));
    arg_expr->kind = INT_LITERAL_ARG;
    arg_expr->value = value;
}

int add_br_instr(DefineSectionState *state) {
    int offset = state->main_data->length;
    BranchInstr *tbr_instr = alloc(state->main_data, ASIZEOF(BranchInstr));
    tbr_instr->base.kind = INSTR_BRANCH;
    return offset;
}

void br_resolve(DefineSectionState *state, int offset, int blk) {
    BranchInstr *br_instr = (BranchInstr*)((char*) state->main_data->ptr + offset);
    br_instr->blk = blk;
}

int add_tbr_instr(DefineSectionState *state, int reg) {
    int offset = state->main_data->length;
    TestBranchInstr *tbr_instr = alloc(state->main_data, ASIZEOF(TestBranchInstr));
    tbr_instr->base.kind = INSTR_TESTBRANCH;
    tbr_instr->reg = reg;
    return offset;
}

void tbr_resolve_then(DefineSectionState *state, int offset, int thenblk) {
    TestBranchInstr *tbr_instr = (TestBranchInstr*)((char*) state->main_data->ptr + offset);
    tbr_instr->then_blk = thenblk;
}

void tbr_resolve_else(DefineSectionState *state, int offset, int elseblk) {
    TestBranchInstr *tbr_instr = (TestBranchInstr*)((char*) state->main_data->ptr + offset);
    tbr_instr->else_blk = elseblk;
}

void add_ret_instr(DefineSectionState *state, int reg) {
    ReturnInstr *ret_instr = alloc(state->main_data, ASIZEOF(ReturnInstr));
    ret_instr->base.kind = INSTR_RETURN;
    ret_instr->reg = reg;
}

int start_block(DefineSectionState *state) {
    state->main_data->length = WORD_ALIGN(state->main_data->length);

    BlockData *block_data = alloc(state->offsets_data, sizeof(BlockData));
    block_data->block_offset = state->main_data->length;
    block_data->register_offset = state->num_registers;
    block_data->regfile_offset = state->regfile_size;
    return state->num_blocks++;
}
