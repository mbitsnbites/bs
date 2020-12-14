# BSVM

The BSVM (BS Virtual Machine) is a simple byte code machine with the following properties:

* 32-bit register machine.
* There are 256 32-bit registers:
  * 254 general purpose registers, R1 - R254.
  * One register is always zero: Z (alias for R0).
  * One register is the stack pointer: SP (alias of R255).
* Variable length instruction encoding (1-6 bytes per instruction).
* A flat memory space (containing both program and data).
* No memory management (memory management is implemented by the byte code).

## Design goals

The BSVM is designed to be feasible to implement in a variety of different languages and environments, including script languages such as Bash and PowerShell.

Furthermore, a BSVM implementation should be very small, so that it is feasible to include the complete runtime along with your BS scripts (for instance in a Git repository or in a tar archive), without requiring any installation or dependencies.

The BS interpreter is compiled for the BSVM target and can thus run on just about any machine, without requiring any installation.

## Instruction encoding

The instruction format is variable length.

The operation is given by the first byte of the instruction. When an operation has several possible operand formats, this is indicated by the two most significant bits of the first byte:

Operation identifier byte:

| Bit | 7 | 6 | 5 | 4 | 3 | 2 | 1 | 0 |
|---|---|---|---|---|---|---|---|---|
|   | AT<sub>1</sub> | AT<sub>0</sub> | OP<sub>5</sub> | OP<sub>4</sub> | OP<sub>3</sub> | OP<sub>2</sub> | OP<sub>1</sub> | OP<sub>0</sub> |

...where OP<sub>5</sub>..OP<sub>0</sub> is the operation (0-63), and AT<sub>1</sub>..AT<sub>0</sub> is the argument type (0-3).

Following the first byte are the operands (in order). The number of operands depends on the instruction (as given by OP). All operands but the last operand must be a register operand, given by a single byte:

| Bit | 7 | 6 | 5 | 4 | 3 | 2 | 1 | 0 |
|---|---|---|---|---|---|---|---|---|
|   | R<sub>7</sub> | R<sub>6</sub> | R<sub>5</sub> | R<sub>4</sub> | R<sub>3</sub> | R<sub>2</sub> | R<sub>1</sub> | R<sub>0</sub> |

There are 254 general purpose registers that can be addressed by instuctions, called R1-R254.

By convention, R0 (a.k.a. Z) is always zero. Additionally there is a stack pointer register, SP (alias for R255), that is implicitly modified by stack manipulation instructions (PUSH, POP, JSR and RTS).

The last operand of an instruction (if any) can have one of the following three operand types (as given by the argument type field, AT, of the first instruction byte):

| AT | Meaning |
|----|---|
| 00 | Register |
| 01 | 8-bit signed immediate value |
| 10 | 8-bit PC-relative offset |
| 11 | 32-bit value (signed immediate or absolute address) |

32-bit values are encoded in little endian format in memory. This applies both to immediate values that are stored in the program code, and values that are stored and loaded with the STW and LDW instructions.

## Instructions

In the following list, the following notation is used:

* R*m*, R*n* - A register (R0-R255)
* X - A generic operand (a register, an immediate value or a memory address)
* [*addr*] - Contents of memory at location *addr*

| OP | Assembler | Operation | Description |
|---|---|---|---|
| 1 | MOV R*m*, X | R*m* ← X | Move value to register |
| 2 | LDB R*m*, R*n*, X | R*m* ← [R*n* + X] | Load unsigned byte |
| 3 | LDW R*m*, R*n*, X | R*m* ← [R*n* + X] | Load word |
| 4 | STB R*m*, R*n*, X | [R*n* + X] ← R*m* | Store byte (lowest 8 bits of R*m*) |
| 5 | STW R*m*, R*n*, X | [R*n* + X] ← R*m* | Store word |
| 6 | JMP X | PC ← X | Jump |
| 7 | JSR X | SP ← SP - 4<br>[SP] ← PC<br>PC ← X | Jump to subroutine |
| 8 | RTS | PC ← [SP]<br>SP ← SP + 4 | Return from subroutine |
| 9 | BEQ X | PC ← X if CC.EQ=1 | Branch if EQual |
| 10 | BNE X | PC ← X if CC.EQ=0 | Branch if Not Equal |
| 11 | BLT X | PC ← X if CC.LT=1 | Branch if Less Than |
| 12 | BLE X | PC ← X if CC.LT=1 or CC.EQ=1 | Branch if Less than or Equal |
| 13 | BGT X | PC ← X if CC.GT=1 | Branch if Greater Than |
| 14 | BGE X | PC ← X if CC.GT=1 or CC.EQ=1 | Branch if Greater than or Equal |
| 15 | CMP R*m*, X | CC ← compare(R*m*, X) | Compare |
| 16 | PUSH R*m* | SP ← SP - 4<br>[SP] ← R*m* | Push register value onto the stack |
| 17 | POP R*m* | R*m* ← [SP]<br>SP ← SP + 4 | Pop register value from the stack |
| 18 | ADD R*m*, X | R*m* ← R*m* + X | Add |
| 19 | SUB R*m*, X | R*m* ← R*m* - X | Subtract |
| 20 | MUL R*m*, X | R*m* ← R*m* * X | Multiply |
| 21 | DIV R*m*, X | R*m* ← R*m* / X | Divide |
| 22 | MOD R*m*, X | R*m* ← R*m* % X | Modulo |
| 23 | AND R*m*, X | R*m* ← R*m* & X | Bitwise and |
| 24 | OR R*m*, X | R*m* ← R*m* \| X | Bitwise or |
| 25 | XOR R*m*, X | R*m* ← R*m* ^ X | Bitwise exclusive or |
| 26 | SHL R*m*, X | R*m* ← R*m* << X | Shift left |
| 27 | SHR R*m*, X | R*m* ← R*m* >> X | Arithmetic shift right |
| 28 | EXIT X | exit(X) | Exit program |
| 29 | PRINTLN X | println(X) | Print string at address X, with new line |
| 30 | PRINT X | print(X) | Print string at address X |
| 31 | RUN X | run(X) | Run system command given by string at address X |
