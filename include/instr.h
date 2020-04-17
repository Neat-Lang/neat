#pragma once

typedef enum {
    INSTR_ARG,
    INSTR_LITERAL,
    INSTR_CALL,
    INSTR_BRANCH,
    INSTR_TESTBRANCH,
    INSTR_RETURN,
    INSTR_ALLOC,
    INSTR_OFFSET_ADDRESS,
    INSTR_LOAD,
    INSTR_STORE,
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
    int value;
} LiteralInstr;

typedef struct {
    BaseInstr base;
    int size;
} AllocInstr;

/**
 * Take register containing a pointer to a struct.
 * Yield the address of a member of the struct.
 */
typedef struct {
    BaseInstr base;
    int reg; // struct
    int index; // member index
    // and then: struct type
} OffsetAddressInstr;

typedef struct {
    BaseInstr base;
    int pointer_reg;
    // and then: value type
} LoadInstr;

typedef struct {
    BaseInstr base;
    int value_reg;
    int pointer_reg;
    // and then: value type
} StoreInstr;

typedef struct {
    BaseInstr base;
    int symbol_offset; // offset from start of file
    int args_num;
    // and then: [args: ArgExpr x args_num]
} CallInstr;

typedef struct {
    BaseInstr base;
    int blk;
} BranchInstr;

typedef struct {
    BaseInstr base;
    int reg;
    int then_blk;
    int else_blk;
} TestBranchInstr;

typedef struct {
    BaseInstr base;
    int reg;
} ReturnInstr;

typedef enum {
    INT_LITERAL_ARG,
    REG_ARG,
} ArgKind;

typedef struct {
    ArgKind kind;
    int value;
} ArgExpr;
