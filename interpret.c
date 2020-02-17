#include <assert.h>
#include <errno.h>
#include <fcntl.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <sys/types.h>

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
    Type ret;
    size_t args_len;
    char name[0];
    // and then: arg types
} Symbol;

typedef enum {
    UNRESOLVED_SYMBOL,
    C_SYMBOL,
    BC_SYMBOL,
} SymbolKind;

typedef void (*callptr_t)(size_t values_len, Value *values_ptr, Value *ret_ptr);

typedef struct {
    SymbolKind kind;
    Symbol *symbol;
    union {
        callptr_t callptr;
        struct {
            Type *arg_types; // cache for offset off symbol
            void *block_data; // blocks_len, [block offsets : size_t], [body : Block]
        };
    };
} SymbolEntry;

typedef struct {
    size_t length;
    SymbolEntry *ptr;
} SymbolTable;

typedef struct  {
    SymbolTable entries;
} Environment;

typedef enum {
    DECLARE_SECTION,
    DEFINE_SECTION
} SectionKind;

typedef struct {
    SectionKind kind;
    size_t length; // including Section header
    // and then: data
} Section;

typedef struct {
    Section base;
    size_t declaration_index;
} DefineSection;

#define WORD_ALIGN(I) ((I + 7) & 0xfffffffffffffff8)
#define ASIZEOF(T) WORD_ALIGN(sizeof(T))

int declare(Environment *environment, Symbol *symbol) {
    printf("declare symbol %s at %li\n", symbol->name, environment->entries.length);
    environment->entries.ptr = realloc(
        environment->entries.ptr, ++environment->entries.length * sizeof(SymbolEntry));
    environment->entries.ptr[environment->entries.length - 1] = (SymbolEntry) {
        .kind = UNRESOLVED_SYMBOL,
        .symbol = symbol
    };
    return environment->entries.length - 1;
}

SymbolEntry *find_symbol(Environment *environment, const char *name) {
    for (size_t i = 0; i < environment->entries.length; i++) {
        SymbolEntry *entry = &environment->entries.ptr[i];

        if (strcmp(entry->symbol->name, name) == 0) {
            return entry;
        }
    }
    fprintf(stderr, "no such symbol: %s\n", name);
    assert(false);
    abort();
}

void resolve_c(Environment *environment, const char *name, callptr_t callptr) {
    SymbolEntry *entry = find_symbol(environment, name);
    entry->kind = C_SYMBOL;
    entry->callptr = callptr;
}

void resolve_bc(Environment *environment, const char *name, void *block_data) {
    SymbolEntry *entry = find_symbol(environment, name);
    const char *symbol_name = entry->symbol->name;
    entry->kind = BC_SYMBOL;
    entry->arg_types = (Type*) WORD_ALIGN((size_t)(symbol_name + strlen(symbol_name) + 1));
    entry->block_data = block_data;
}

void call(Environment *environment, SymbolEntry *entry, size_t values_len, Value *values_ptr, Value *ret_ptr) {
    assert(entry->symbol->args_len == values_len);
    assert(entry->kind != UNRESOLVED_SYMBOL);

    if (entry->kind == C_SYMBOL) {
        entry->callptr(values_len, values_ptr, ret_ptr);
        return;
    }
    assert(entry->kind == BC_SYMBOL);

    size_t *block_offsets = (size_t*) entry->block_data;
    int blkid = 0; // entry

    while (true) {
        Block *blk = (Block*)((char*) entry->symbol + block_offsets[blkid]);
        // printf(" blk %i (%li) %p\n", blkid, blk->slot_types_len, (void*) blk);
        Type *type_cur = (Type*)((char*) blk + ASIZEOF(Block));
        for (int i = 0; i < blk->slot_types_len; i++) {
            type_cur = (Type*)((char*) type_cur + ASIZEOF(Type)); // TODO handle types with dynamic size
        }
        // fill in lazily as you walk instructions
        Value values[blk->slot_types_len];
        BaseInstr *instr = (BaseInstr*) type_cur; // instrs start after types
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
                    SymbolEntry *entry = &environment->entries.ptr[callinstr->symbol_offset];
                    // char *symbol_name = (char*) entry->symbol + ASIZEOF(Symbol);
                    // printf("    call %s(%i, %i)\n", symbol_name, call_args[0].int_value, call_args[1].int_value);
                    call(environment, entry, callinstr->args_num, call_args, current_value);
                    assert(current_value->type.kind == INT);
                    instr = (BaseInstr*) (
                        (char*) instr
                        + ASIZEOF(CallInstr)
                        + ASIZEOF(ArgExpr) * callinstr->args_num);
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

typedef struct {
    void *ptr;
    size_t length;
} Data;

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

size_t begin_define_section(Data *data, size_t index) {
    size_t start = data->length;
    DefineSection *define_section = alloc(data, ASIZEOF(DefineSection));
    define_section->base.kind = DEFINE_SECTION;
    define_section->declaration_index = index;
    return start;
}

void end_section(Data *data, size_t start) {
    size_t length = data->length - start;

    Section *section = (Section*)((char*) data->ptr + start);
    section->length = length;
}

void add_type_int(Data *data) {
    Type *type = alloc(data, ASIZEOF(Type));
    type->kind = INT;
}

void add_string(Data *data, const char* text) {
    char *target = alloc(data, WORD_ALIGN(strlen(text) + 1));
    strcpy(target, text);
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

void start_block(Data *data, size_t symbol_base_offset, size_t *offset_ptr, size_t slot_types_len) {
    data->length = WORD_ALIGN(data->length);
    *offset_ptr = data->length - symbol_base_offset;
    Block *block = alloc(data, ASIZEOF(Block));
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
    int write_bc = 0;

    if (write_bc) {
        Data file_data = { .ptr = NULL, .length = 0 };

        int int_eq_offset = 0;
        size_t int_eq_section = begin_declare_section(&file_data);
        Symbol *int_eq = alloc(&file_data, ASIZEOF(Symbol));
        int_eq->ret.kind = INT;
        int_eq->args_len = 2;
        add_string(&file_data, "int_eq");
        add_type_int(&file_data);
        add_type_int(&file_data);
        end_section(&file_data, int_eq_section);

        int int_add_offset = 1;
        size_t int_add_section = begin_declare_section(&file_data);
        Symbol *int_add = alloc(&file_data, ASIZEOF(Symbol));
        int_add->ret.kind = INT;
        int_add->args_len = 2;
        add_string(&file_data, "int_add");
        add_type_int(&file_data);
        add_type_int(&file_data);
        end_section(&file_data, int_add_section);

        int int_sub_offset = 2;
        size_t int_sub_section = begin_declare_section(&file_data);
        Symbol *int_sub = alloc(&file_data, ASIZEOF(Symbol));
        int_sub->ret.kind = INT;
        int_sub->args_len = 2;
        add_string(&file_data, "int_sub");
        add_type_int(&file_data);
        add_type_int(&file_data);
        end_section(&file_data, int_sub_section);

        int ack_offset = 3;
        size_t ack_declare_section = begin_declare_section(&file_data);
        size_t ack_byte_offset = file_data.length;
        Symbol *ack = alloc(&file_data, ASIZEOF(Symbol));
        ack->ret.kind = INT;
        ack->args_len = 2;
        add_string(&file_data, "ack");
        add_type_int(&file_data);
        add_type_int(&file_data);
        end_section(&file_data, ack_declare_section);

        size_t ack_define_section = begin_define_section(&file_data, ack_offset);
        size_t block_offsets_offset = alloc_block_offsets(&file_data, 5);
    #define BLOCK_OFFSETS ((size_t*)((char*) file_data.ptr + block_offsets_offset))
        // block 0
        start_block(&file_data, ack_byte_offset, &BLOCK_OFFSETS[0], 2);
        add_type_int(&file_data);
        add_type_int(&file_data);
        add_arg_instr(&file_data, 0); // 0
        start_call_instr(&file_data, int_eq_offset, 2); // 1
        add_call_slot_arg(&file_data, 0);
        add_call_int_arg(&file_data, 0);
        add_tbr_instr(&file_data, 1, 1, 2);
        // block 1
        start_block(&file_data, ack_byte_offset, &BLOCK_OFFSETS[1], 2);
        add_type_int(&file_data);
        add_type_int(&file_data);
        add_arg_instr(&file_data, 1); // 0
        start_call_instr(&file_data, int_add_offset, 2); // 1
        add_call_slot_arg(&file_data, 0);
        add_call_int_arg(&file_data, 1);
        add_ret_instr(&file_data, 1);
        // block 2
        start_block(&file_data, ack_byte_offset, &BLOCK_OFFSETS[2], 2);
        add_type_int(&file_data);
        add_type_int(&file_data);
        add_arg_instr(&file_data, 1);
        start_call_instr(&file_data, int_eq_offset, 2);
        add_call_slot_arg(&file_data, 0);
        add_call_int_arg(&file_data, 0);
        add_tbr_instr(&file_data, 1, 3, 4);
        // block 3
        start_block(&file_data, ack_byte_offset, &BLOCK_OFFSETS[3], 3);
        for (int i = 0; i < 3; i++) add_type_int(&file_data);
        add_arg_instr(&file_data, 0); // %0 = arg(0)
        start_call_instr(&file_data, int_sub_offset, 2); // %1 = int_sub(%0, 1)
        add_call_slot_arg(&file_data, 0);
        add_call_int_arg(&file_data, 1);
        start_call_instr(&file_data, ack_offset, 2); // %2 = ack(%1, 1)
        add_call_slot_arg(&file_data, 1);
        add_call_int_arg(&file_data, 1);
        add_ret_instr(&file_data, 2);
        // block 4
        start_block(&file_data, ack_byte_offset, &BLOCK_OFFSETS[4], 6);
        for (int i = 0; i < 6; i++) add_type_int(&file_data);
        add_arg_instr(&file_data, 1); // 0
        start_call_instr(&file_data, int_sub_offset, 2); // 1
        add_call_slot_arg(&file_data, 0);
        add_call_int_arg(&file_data, 1);
        add_arg_instr(&file_data, 0); // 2
        start_call_instr(&file_data, ack_offset, 2); // 3
        add_call_slot_arg(&file_data, 2);
        add_call_slot_arg(&file_data, 1);
        start_call_instr(&file_data, int_sub_offset, 2); // 4
        add_call_slot_arg(&file_data, 2);
        add_call_int_arg(&file_data, 1);
        start_call_instr(&file_data, ack_offset, 2); // 5
        add_call_slot_arg(&file_data, 4);
        add_call_slot_arg(&file_data, 3);
        add_ret_instr(&file_data, 5);
        end_section(&file_data, ack_define_section);

        FILE *bcfile = fopen("ack.bc", "w");
        fwrite(file_data.ptr, 1, file_data.length, bcfile);
        fclose(bcfile);
    }

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
