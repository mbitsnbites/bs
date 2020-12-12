# BSVM

The BSVM (BS Virtual Machine) is a simple byte code machine with the following properties:

* 32-bit register machine.
* There are 256 32-bit registers:
  * 254 general purpose registers, R1 - R254.
  * One register is always zero: Z (alias for R0).
  * One register is the stack pointer: SP.
* Variable length instruction encoding (1-6 bytes per instruction).
* A flat memory space containing (both program and data).
* No memory management (memory management is implemented by the byte code).

## Design goals

The BSVM is designed to be feasible to implement in a variety of different languages and environments, including classic script languages such as Bash and BAT. 

Furthermore, a BSVM implementation should be very small, so that it is feasible to include the complete runtime along with your BS scripts (for instance in a Git repository or in a tar archive), without requiring any installation or dependencies.

The BS interpreter is compiled for the BSVM target and can thus run on just about any machine, without requiring any installation.

## Instruction encoding

TBD

## Instructions

TBD
