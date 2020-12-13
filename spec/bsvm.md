# BSVM

The BSVM (BS Virtual Machine) is a simple byte code machine with the following properties:

* 32-bit register machine.
* There are 256 32-bit registers:
  * 254 general purpose registers, R1 - R254.
  * One register is always zero: Z (alias for R0).
  * One register is the stack pointer: SP (alias of R255).
* Variable length instruction encoding (1-6 bytes per instruction).
* A flat memory space containing (both program and data).
* No memory management (memory management is implemented by the byte code).

## Design goals

The BSVM is designed to be feasible to implement in a variety of different languages and environments, including classic script languages such as Bash and BAT. 

Furthermore, a BSVM implementation should be very small, so that it is feasible to include the complete runtime along with your BS scripts (for instance in a Git repository or in a tar archive), without requiring any installation or dependencies.

The BS interpreter is compiled for the BSVM target and can thus run on just about any machine, without requiring any installation.

## Instruction encoding

The instruction format is variable length.

The operation is given by the first byte of the instruction. When an operation has several possible operand formats, this is indicated by the two most significant bits of the first byte:

Operation identifyer byte:

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

TBD
