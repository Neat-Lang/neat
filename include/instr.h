#pragma once

typedef enum {
    INSTR_ARG,
    INSTR_LITERAL,
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
    int value;
} LiteralInstr;

typedef struct {
    BaseInstr base;
    int symbol_offset;
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
