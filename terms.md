## Terms used in cx

### Block

Short for 'basic block', a series of instructions executed in order and terminated by a branch instruction.
Analogously, every branch instruction jumps to the start of a block.

### stackframe, frame

A struct that may be allocated at function entry to hold the language variables used in the function.

### register file, regfile

As the bytecode consists of a series of blocks of register assignments, the regfile is a flat area of
memory containing the values of each instruction. Compared to the stackframe, it is allocated implicitly
by the interpreter.
