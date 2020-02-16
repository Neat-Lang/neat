int ack(int, int);
int int_eq(int, int);
int int_add(int, int);
int int_sub(int, int);

int ack(int, int):
0:
int *1 = int_eq(arg0, 0)
void *0 = tbr *0, 1:, 2:

1:
int *2 = int_add(arg1, 1)
void *0 = ret *1

2:
int *3 = int_eq(arg1, 0)
void *0 = tbr *2, 3:, 4:

3:
int *4 = int_sub(arg1, 1)
int *5 = ack(*3, 1)
void *0 = ret *5

4:
int *6 = int_sub(arg1, 1)
int *7 = ack(arg0, *5)
int *8 = int_sub(arg0, 1)
int *9 = ack(*7, *6)
void *0 = ret *9

struct Symbol
{
  int length;
  char* text;
}

struct SymbolTable
{
  int length;
  Symbol *data;
}

struct Declaration
{
  int symbol;
  int numblocks;
  Block[0] blocks;
}

struct Block
{
  int length;
  Instruction[0] instructions;
}

enum TypeKind
{
  INT,
  VOID,
}

struct Type
{
  TypeKind kind;
}

struct Reg
{
  int index;
  Type type;
}

struct Instruction
{
  int kind;
  Reg target;
}

struct Value
{
  enum { Register, FunctionArg, IntLiteral } kind;
  int value;
}

struct CallInstruction
{
  Instruction base;
  int numArgs;
  Value[0] args;
}

...?

CxBc 0.0.1\n
[4b text segment length]
[text segment]
[4b SymbolTable length]
[list of pairs of symbol length, offset into text segment]
[4b declarations]
