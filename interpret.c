#include <alloca.h>
#include <assert.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef enum {
    INSTR_ARG,
    INSTR_CALL,
    INSTR_BRANCH,
    INSTR_TESTBRANCH,
    INSTR_RETURN,
} InstrKind;

typedef struct {
    InstrKind kind;
} BaseInstr;

typedef struct {
    BaseInstr base;
    int index;
} ArgInstr;

typedef struct {
    BaseInstr base;
    size_t symbol_offset;
    int args_num;
    // and then: [args: ArgExpr x args_num]
} CallInstr;

typedef struct {
    BaseInstr base;
    int slot;
    int then_blk;
    int else_blk;
} TestBranchInstr;

typedef struct {
    BaseInstr base;
    int slot;
} ReturnInstr;

typedef enum {
    INT_LITERAL_ARG,
    SLOT_ARG,
} ArgKind;

typedef struct {
    ArgKind kind;
    int value;
} ArgExpr;

typedef enum {
    INT,
    VOID
} TypeKind;

typedef struct {
    TypeKind kind;
} Type;

typedef struct {
    Type type;
    int int_value;
} Value;

typedef struct {
    size_t slot_types_len;
    // and then: [slot type: Type], [Instr]
} Block;

typedef struct {
    const char *name;
    void (*callptr)(size_t values_len, Value *values_ptr, Value *ret_ptr);
    Type ret;
    size_t args_len;
    size_t blocks_len;
    // and then: arg types, [block offsets : size_t], [body : Block]
} Symbol;

typedef struct {
    size_t length;
    Symbol **ptr;
} SymbolTable;

typedef struct  {
    SymbolTable symbols;
} Environment;

Symbol *find_symbol(Environment *environment, const char *name) {
    for (size_t i = 0; i < environment->symbols.length; i++) {
        Symbol *symbol = environment->symbols.ptr[i];

        if (strcmp(symbol->name, name) == 0) {
            return symbol;
        }
    }
    fprintf(stderr, "no such symbol: %s\n", name);
    assert(false);
}

int add_symbol(Environment *environment, Symbol *symbol) {
    environment->symbols.ptr = realloc(environment->symbols.ptr, ++environment->symbols.length * sizeof(Symbol*));
    environment->symbols.ptr[environment->symbols.length - 1] = symbol;
    return environment->symbols.length - 1;
}

#define WORD_ALIGN(I) ((I + 7) & 0xfffffffffffffff8)
#define ASIZEOF(T) WORD_ALIGN(sizeof(T))

void call(Environment *environment, Symbol *symbol, size_t values_len, Value *values_ptr, Value *ret_ptr) {
    assert(symbol->args_len == values_len);

    if (symbol->callptr != NULL) {
        symbol->callptr(values_len, values_ptr, ret_ptr);
        return;
    }

    Type *arg_types_cur = (Type*)((char*) symbol + ASIZEOF(Symbol));
    for (int i = 0; i < symbol->args_len; i++) {
        arg_types_cur = (Type*)((char*) arg_types_cur + ASIZEOF(Type)); // TODO
    }
    size_t *block_offsets = (size_t*) arg_types_cur;
    int blkid = 0; // entry

    while (true) {
        Block *blk = (Block*)((char*) symbol + block_offsets[blkid]);
        // printf(" blk %i (%li) %p\n", blkid, blk->slot_types_len, (void*) blk);
        Type *type_cur = (Type*)((char*) blk + ASIZEOF(Block));
        int regsz = 0;
        Type **types = alloca(sizeof(Type*) * blk->slot_types_len);
        for (int i = 0; i < blk->slot_types_len; i++) {
            types[i] = type_cur;
            if (type_cur->kind == INT) {
                regsz += 4;
            }
            type_cur = (Type*)((char*) type_cur + ASIZEOF(Type)); // TODO
        }
        char *blkreg = alloca(regsz);
        // fill in lazily as you walk instructions
        Value *values = alloca(blk->slot_types_len * ASIZEOF(Value));
        BaseInstr *instr = (BaseInstr*) type_cur; // instrs start after types
        for (int instr_id = 0; instr_id < blk->slot_types_len; instr_id++) {
            // printf("  instr %i = %i %p\n", instr_id, instr->kind, (void*) instr);
            Type *type = types[instr_id];
            switch (instr->kind) {
                case INSTR_ARG:
                {
                    ArgInstr *arginstr = (ArgInstr*) instr;
                    *(int*) blkreg = values_ptr[arginstr->index].int_value;
                    instr = (BaseInstr*) ((char*) instr + ASIZEOF(ArgInstr));
                }
                break;
                case INSTR_CALL:
                {
                    CallInstr *callinstr = (CallInstr*) instr;
                    Value *call_args = alloca(callinstr->args_num * ASIZEOF(Value));
                    for (int arg_id = 0; arg_id < callinstr->args_num; arg_id++) {
                        ArgExpr arg_expr = ((ArgExpr*)(callinstr + 1))[arg_id];
                        switch (arg_expr.kind) {
                            case INT_LITERAL_ARG:
                                call_args[arg_id].type.kind = INT;
                                call_args[arg_id].int_value = arg_expr.value;
                                break;
                            case SLOT_ARG:
                                call_args[arg_id] = values[arg_expr.value];
                                break;
                            default:
                                assert(false);
                        }
                    }
                    Symbol *symbol = environment->symbols.ptr[callinstr->symbol_offset];
                    // printf("call %s(%i, %i)\n", symbol->name, call_args[0].int_value, call_args[1].int_value);
                    Value call_ret;
                    call(environment, symbol, callinstr->args_num, call_args, &call_ret);
                    assert(call_ret.type.kind == INT);
                    *(int*) blkreg = call_ret.int_value;
                    instr = (BaseInstr*) (
                        (char*) instr
                        + ASIZEOF(CallInstr)
                        + ASIZEOF(ArgExpr) * callinstr->args_num);
                }
                break;
                default:
                    assert(false);
            }
            if (type->kind == INT) {
                values[instr_id].type.kind = INT;
                values[instr_id].int_value = *(int*) blkreg;
                blkreg += 4;
            }
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

typedef struct {
    void *ptr;
    size_t length;
} Data;

void *alloc(Data *data, size_t size)
{
    size_t prev_length = data->length;
    data->length += size;
    data->ptr = realloc(data->ptr, data->length);
    return (char*) data->ptr + prev_length;
}

void add_type_int(Data *data) {
    Type *type = alloc(data, ASIZEOF(Type));
    type->kind = INT;
}

void add_arg_instr(Data *data, int index) {
    ArgInstr *arg_instr = alloc(data, ASIZEOF(ArgInstr));
    arg_instr->base.kind = INSTR_ARG;
    arg_instr->index = index;
}

void start_call_instr(Data *data, int offset, int args) {
    CallInstr *call_instr = alloc(data, ASIZEOF(CallInstr));
    call_instr->base.kind = INSTR_CALL;
    call_instr->symbol_offset = offset;
    call_instr->args_num = args;
}

void add_call_slot_arg(Data *data, int slotid) {
    ArgExpr *arg_expr = alloc(data, ASIZEOF(ArgExpr));
    arg_expr->kind = SLOT_ARG;
    arg_expr->value = slotid;
}

void add_call_int_arg(Data *data, int value) {
    ArgExpr *arg_expr = alloc(data, ASIZEOF(ArgExpr));
    arg_expr->kind = INT_LITERAL_ARG;
    arg_expr->value = value;
}

void add_tbr_instr(Data *data, int slot, int blkthen, int blkelse) {
    TestBranchInstr *tbr_instr = alloc(data, ASIZEOF(TestBranchInstr));
    tbr_instr->base.kind = INSTR_TESTBRANCH;
    tbr_instr->slot = slot;
    tbr_instr->then_blk = blkthen;
    tbr_instr->else_blk = blkelse;
}

void add_ret_instr(Data *data, int slot) {
    ReturnInstr *ret_instr = alloc(data, ASIZEOF(ReturnInstr));
    ret_instr->base.kind = INSTR_RETURN;
    ret_instr->slot = slot;
}

size_t alloc_block_offsets(Data *data, size_t num_offsets) {
    size_t offset = data->length;
    alloc(data, sizeof(size_t) * num_offsets);
    return offset;
}

void start_block(Data *data, size_t *offset_ptr, size_t slot_types_len) {
    data->length = WORD_ALIGN(data->length);
    *offset_ptr = data->length;
    Block *block = alloc(data, sizeof(Block));
    block->slot_types_len = slot_types_len;
}

void int_eq_fn(size_t arg_len, Value *arg_ptr, Value *ret_ptr) {
    assert(arg_len == 2);
    assert(arg_ptr[0].type.kind == INT);
    assert(arg_ptr[1].type.kind == INT);
    ret_ptr->type.kind = INT;
    ret_ptr->int_value = arg_ptr[0].int_value == arg_ptr[1].int_value;
}

void int_add_fn(size_t arg_len, Value *arg_ptr, Value *ret_ptr) {
    assert(arg_len == 2);
    assert(arg_ptr[0].type.kind == INT);
    assert(arg_ptr[1].type.kind == INT);
    ret_ptr->type.kind = INT;
    ret_ptr->int_value = arg_ptr[0].int_value + arg_ptr[1].int_value;
}

void int_sub_fn(size_t arg_len, Value *arg_ptr, Value *ret_ptr) {
    assert(arg_len == 2);
    assert(arg_ptr[0].type.kind == INT);
    assert(arg_ptr[1].type.kind == INT);
    ret_ptr->type.kind = INT;
    ret_ptr->int_value = arg_ptr[0].int_value - arg_ptr[1].int_value;
}

int main(int argc, const char **argv) {
    Environment environment = { 0 };
    Symbol *int_eq = malloc(sizeof(Symbol) + sizeof(Type) * 2);
    int_eq->name = "int_eq";
    int_eq->ret.kind = INT;
    int_eq->args_len = 2;
    int_eq->callptr = int_eq_fn;
    ((Type*) (int_eq + 1))[0].kind = INT;
    ((Type*) (int_eq + 1))[1].kind = INT;
    int int_eq_offset = add_symbol(&environment, int_eq);

    Symbol *int_add = malloc(sizeof(Symbol) + sizeof(Type) * 2);
    int_add->name = "int_add";
    int_add->ret.kind = INT;
    int_add->args_len = 2;
    int_add->callptr = int_add_fn;
    ((Type*) (int_add + 1))[0].kind = INT;
    ((Type*) (int_add + 1))[1].kind = INT;
    int int_add_offset = add_symbol(&environment, int_add);

    Symbol *int_sub = malloc(sizeof(Symbol) + sizeof(Type) * 2);
    int_sub->name = "int_sub";
    int_sub->ret.kind = INT;
    int_sub->args_len = 2;
    int_sub->callptr = int_sub_fn;
    ((Type*) (int_sub + 1))[0].kind = INT;
    ((Type*) (int_sub + 1))[1].kind = INT;
    int int_sub_offset = add_symbol(&environment, int_sub);

    Symbol *ack = malloc(sizeof(Symbol));
    ack->name = "ack";
    ack->ret.kind = INT;
    ack->args_len = 2;
    ack->blocks_len = 5;
    ack->callptr = NULL;
    int ack_offset = environment.symbols.length;
    Data ack_data = { .ptr = ack, .length = sizeof(Symbol) };
    add_type_int(&ack_data);
    add_type_int(&ack_data);
    size_t block_offsets_offset = alloc_block_offsets(&ack_data, 5);
#define BLOCK_OFFSETS ((size_t*)((char*) ack_data.ptr + block_offsets_offset))
    // block 0
    start_block(&ack_data, &BLOCK_OFFSETS[0], 2);
    add_type_int(&ack_data);
    add_type_int(&ack_data);
    add_arg_instr(&ack_data, 0); // 0
    start_call_instr(&ack_data, int_eq_offset, 2); // 1
    add_call_slot_arg(&ack_data, 0);
    add_call_int_arg(&ack_data, 0);
    add_tbr_instr(&ack_data, 1, 1, 2);
    // block 1
    start_block(&ack_data, &BLOCK_OFFSETS[1], 2);
    add_type_int(&ack_data);
    add_type_int(&ack_data);
    add_arg_instr(&ack_data, 1); // 0
    start_call_instr(&ack_data, int_add_offset, 2); // 1
    add_call_slot_arg(&ack_data, 0);
    add_call_int_arg(&ack_data, 1);
    add_ret_instr(&ack_data, 1);
    // block 2
    start_block(&ack_data, &BLOCK_OFFSETS[2], 2);
    add_type_int(&ack_data);
    add_type_int(&ack_data);
    add_arg_instr(&ack_data, 1);
    start_call_instr(&ack_data, int_eq_offset, 2);
    add_call_slot_arg(&ack_data, 0);
    add_call_int_arg(&ack_data, 0);
    add_tbr_instr(&ack_data, 1, 3, 4);
    // block 3
    start_block(&ack_data, &BLOCK_OFFSETS[3], 3);
    for (int i = 0; i < 3; i++) add_type_int(&ack_data);
    add_arg_instr(&ack_data, 0); // %0 = arg(0)
    start_call_instr(&ack_data, int_sub_offset, 2); // %1 = int_sub(%0, 1)
    add_call_slot_arg(&ack_data, 0);
    add_call_int_arg(&ack_data, 1);
    start_call_instr(&ack_data, ack_offset, 2); // %2 = ack(%1, 1)
    add_call_slot_arg(&ack_data, 1);
    add_call_int_arg(&ack_data, 1);
    add_ret_instr(&ack_data, 2);
    // block 4
    start_block(&ack_data, &BLOCK_OFFSETS[4], 6);
    for (int i = 0; i < 6; i++) add_type_int(&ack_data);
    add_arg_instr(&ack_data, 1); // 0
    start_call_instr(&ack_data, int_sub_offset, 2); // 1
    add_call_slot_arg(&ack_data, 0);
    add_call_int_arg(&ack_data, 1);
    add_arg_instr(&ack_data, 0); // 2
    start_call_instr(&ack_data, ack_offset, 2); // 3
    add_call_slot_arg(&ack_data, 2);
    add_call_slot_arg(&ack_data, 1);
    start_call_instr(&ack_data, int_sub_offset, 2); // 4
    add_call_slot_arg(&ack_data, 2);
    add_call_int_arg(&ack_data, 1);
    start_call_instr(&ack_data, ack_offset, 2); // 5
    add_call_slot_arg(&ack_data, 4);
    add_call_slot_arg(&ack_data, 3);
    add_ret_instr(&ack_data, 5);
    ack = (Symbol*) ack_data.ptr;
    add_symbol(&environment, ack);
    // whew...
#undef BLOCK_OFFSETS
    Symbol *symbol = find_symbol(&environment, "ack");
    Value ret;
    Value *args = alloca(sizeof(Value) * 2);
    args[0].type.kind = INT;
    args[0].int_value = 3;
    args[1].type.kind = INT;
    args[1].int_value = 8;
    for (int i = 0; i < 10; i++) {
        call(&environment, symbol, 2, args, &ret);
        printf("ack(%i, %i) = %i\n", args[0].int_value, args[1].int_value, ret.int_value);
    }
    return 0;
}
