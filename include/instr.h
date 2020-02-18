#pragma once

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
    int symbol_offset;
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
