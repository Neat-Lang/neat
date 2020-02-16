# bytecode

file = header symbol*
symbol = <name> <ret:type> <args:type>* <body>?

body = <decls> <blocks>

decls = <decl>*
decl = <instr>

blocks = <block>*
block = <instr>* <branchinstr>

instr = <slotid:int> <type> "=" (<arg> | <call>)
branchinstr = <branch> | <testbranch> | <return>

type = "int"

arg = <argid:int>
call = <symbol> <expr>*

expr = <literal:int> | <slotid:int>

branch = <targetblk:int>
testbranch = <slotid:int> <thenblk:int> <elseblk:int>
return = <slotid:int>
