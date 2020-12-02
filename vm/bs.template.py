#!/usr/bin/env python3
# -*- mode: python; tab-width: 2; indent-tabs-mode: nil; -*-
# -------------------------------------------------------------------------------------------------
# Copyright (c) 2020 Marcus Geelnard
#
# This software is provided 'as-is', without any express or implied warranty. In no event will the
# authors be held liable for any damages arising from the use of this software.
#
# Permission is granted to anyone to use this software for any purpose, including commercial
# applications, and to alter it and redistribute it freely, subject to the following restrictions:
#
#  1. The origin of this software must not be misrepresented; you must not claim that you wrote
#     the original software. If you use this software in a product, an acknowledgment in the
#     product documentation would be appreciated but is not required.
#
#  2. Altered source versions must be plainly marked as such, and must not be misrepresented as
#     being the original software.
#
#  3. This notice may not be removed or altered from any source distribution.
# -------------------------------------------------------------------------------------------------

from __future__ import print_function
import array, os, sys

# Define the BS VM program. We use a packed string (3 characters per 2 bytes).
prg="DON'T MODIFY THIS LINE! IT IS REPLACED BY THE BUILD PROCESS!"

# Helper functions.
def WriteDebug(s):
  print("DEBUG: " + s, file=sys.stderr)

def getString(a):
  # Read the string length (32-bit integer).
  l=ram[a] | (ram[a+1] << 8) | (ram[a+2] << 16) | (ram[a+3] << 24)

  # Extract the string from memory.
  a+=4
  return ram[a:(a+l)].decode("utf-8")

# Constants.
_EQ=1
_LT=2
_GT=4

# Instruction operand configuration (one element per instruction).
#
#  * nout - Number of output (or in/out) register operands.
#  * ninr - Number of input register operands.
#  * ninx - Number of "final" input operands (any operand kind).
#
# OP:                     1 1 1 1 1 1 1 1 1 1 2 2 2 2 2 2 2 2 2 2 3 3
#     0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
nout=[0,1,1,1,0,0,0,0,0,0,0,0,0,0,0,0,0,1,1,1,1,1,1,1,1,1,1,1,0,0,0,0]
ninr=[0,0,0,0,1,1,0,0,0,0,0,0,0,0,0,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0]
ninx=[0,1,1,1,1,1,1,1,0,1,1,1,1,1,1,1,1,0,1,1,1,1,1,1,1,1,1,1,1,1,1,1]

# Create RAM.
ram=bytearray(1<<20)

# Clear execution state.
pc=0
instrPC=0
cc=0
reg=array.array('l',(0 for i in range(0,256)))

# Convert the packed string to bytes and store it in the RAM.
prg_size=(len(prg)*2)//3
WriteDebug("prg_size="+str(prg_size))
for i in range(0,prg_size//2):
  c1=ord(prg[i*3])-40    # 6 bits (0-63)
  c2=ord(prg[i*3+1])-40  # 5 bits (0-31)
  c3=ord(prg[i*3+2])-40  # 5 bits (0-31)
  b1=(c1 << 2) | (c2 >> 3)
  b2=((c2 & 7) << 5) | c3
  ram[i*2]=b1
  ram[i*2+1]=b2
  WriteDebug("(c1,c2,c3)=({},{},{}) -> ({},{})".format(c1,c2,c3,b1,b2))

# Main execution loop.
exit_code=1
running=True
while running:
  # Read the next opcode.
  instrPC=pc
  op=ram[pc]
  pc+=1

  # Decode the opcode:
  #   Bits 0-5: operation
  #   Bits 6-7: argument type
  arg_type=op >> 6
  operation=op & 63

  WriteDebug("PC={} CC={} OP={} OP*={} AT={}".format(instrPC,cc,op,operation,arg_type))

  # Read the operands.
  ops=[]
  for i in range(nout[operation]):
    # Get register number (0-255)
    ops.append(ram[pc])
    pc+=1
  for i in range(ninr[operation]):
    # Get register value
    ops.append(reg[ram[pc]])
    pc+=1
  for i in range(ninx[operation]):
    if arg_type == 3:
      # 32-bit immediate.
      v=ram[pc] | (ram[pc+1] << 8) | (ram[pc+2] << 16) | (ram[pc+3] << 24)
      pc+=4
    else:
      # Arg types 0-2 use a single byte.
      v=ram[pc]
      pc+=1

      if arg_type == 0:
        # Register value.
        v=reg[v]
      else:
        # Convert unsigned to signed byte (-128..127).
        if v > 127:
          v=v - 256

        if arg_type == 2:
          # 8-bit PC-relative offset.
          v+=instrPC
        # else v=v (arg_type=1, 8-bit signed immedate)
    ops.append(v)

  # Execute the instruction.
  if operation == 1: # MOV
    WriteDebug("MOV R{}, {}".format(ops[0],ops[1]))
    reg[ops[0]]=ops[1]

  elif operation == 2: # LDB
    WriteDebug("LDB R{}, {}".format(ops[0],ops[1]))
    reg[ops[0]]=ram[ops[1]]

  elif operation == 3: # LDW
    WriteDebug("LDW R{}, {}".format(ops[0],ops[1]))
    a=ops[1]
    reg[ops[0]]=ram[a] | (ram[a+1] << 8) | (ram[a+2] << 16) | (ram[a+3] << 24)

  elif operation == 4: # STB
    WriteDebug("STB {}, {}".format(ops[0],ops[1]))
    ram[ops[1]]=ops[0] & 255

  elif operation == 5: # STW
    WriteDebug("STW {}, {}".format(ops[0],ops[1]))
    a=ops[1]
    v=ops[0]
    ram[a]=v & 255
    ram[a+1]=(v >> 8) & 255
    ram[a+2]=(v >> 16) & 255
    ram[a+3]=(v >> 24) & 255

  elif operation == 6: # JMP
    WriteDebug("JMP {}".format(ops[0]))
    pc=ops[0]

  elif operation == 7: # JSR
    WriteDebug("JSR {}".format(ops[0]))
    reg[0]-=4  # Pre-decrement SP
    a=reg[0]
    ram[a]=pc & 255
    ram[a+1]=(pc >> 8) & 255
    ram[a+2]=(pc >> 16) & 255
    ram[a+3]=(pc >> 24) & 255
    pc=ops[0]

  elif operation == 8: # RTS
    WriteDebug("RTS")
    a=reg[0]
    pc=ram[a] | (ram[a+1] << 8) | (ram[a+2] << 16) | (ram[a+3] << 24)
    reg[0]+=4  # Post-increment SP

  elif operation == 9: # BEQ
    WriteDebug("BEQ {}".format(ops[0]))
    if cc & _EQ != 0:
      pc=ops[0]

  elif operation == 10: # BNE
    WriteDebug("BNE {}".format(ops[0]))
    if cc & _EQ == 0:
      pc=ops[0]

  elif operation == 11: # BLT
    WriteDebug("BLT {}".format(ops[0]))
    if cc & _LT != 0:
      pc=ops[0]

  elif operation == 12: # BLE
    WriteDebug("BLE {}".format(ops[0]))
    if cc & (_LT|_EQ) != 0:
      pc=ops[0]

  elif operation == 13: # BGT
    WriteDebug("BGT {}".format(ops[0]))
    if cc & _GT != 0:
      pc=ops[0]

  elif operation == 14: # BGE
    WriteDebug("BGE {}".format(ops[0]))
    if cc & (_GT|_EQ) != 0:
      pc=ops[0]

  elif operation == 15: # CMP
    WriteDebug("CMP {}, {}".format(ops[0],ops[1]))
    cc=0
    if ops[0] == ops[1]:
      cc|=_EQ
    if ops[0] < ops[1]:
      cc|=_LT
    if ops[0] > ops[1]:
      cc|=_GT

  elif operation == 16: # PUSH
    WriteDebug("PUSH {}".format(ops[0]))
    reg[0]-=4  # Pre-decrement SP
    a=reg[0]
    v=ops[0]
    ram[a]=v & 255
    ram[a+1]=(v >> 8) & 255
    ram[a+2]=(v >> 16) & 255
    ram[a+3]=(v >> 24) & 255

  elif operation == 17: # POP
    WriteDebug("POP R{}".format(ops[0]))
    a=reg[0]
    reg[ops[0]]=ram[a] | (ram[a+1] << 8) | (ram[a+2] << 16) | (ram[a+3] << 24)
    reg[0]+=4  # Post-increment SP

  elif operation == 18: # ADD
    WriteDebug("ADD R{}, {}".format(ops[0],ops[1]))
    reg[ops[0]]+=ops[1]

  elif operation == 19: # SUB
    WriteDebug("SUB R{}, {}".format(ops[0],ops[1]))
    reg[ops[0]]-=ops[1]

  elif operation == 20: # MUL
    WriteDebug("MUL R{}, {}".format(ops[0],ops[1]))
    reg[ops[0]]*=ops[1]

  elif operation == 21: # DIV
    WriteDebug("DIV R{}, {}".format(ops[0],ops[1]))
    reg[ops[0]]//=ops[1]

  elif operation == 22: # MOD
    WriteDebug("MOD R{}, {}".format(ops[0],ops[1]))
    reg[ops[0]]%=ops[1]

  elif operation == 23: # AND
    WriteDebug("AND R{}, {}".format(ops[0],ops[1]))
    reg[ops[0]]&=ops[1]

  elif operation == 24: # OR
    WriteDebug("OR R{}, {}".format(ops[0],ops[1]))
    reg[ops[0]]|=ops[1]

  elif operation == 25: # XOR
    WriteDebug("XOR R{}, {}".format(ops[0],ops[1]))
    reg[ops[0]]^=ops[1]

  elif operation == 26: # SHL
    WriteDebug("SHL R{}, {}".format(ops[0],ops[1]))
    reg[ops[0]]<<=ops[1]

  elif operation == 27: # SHR
    WriteDebug("SHR R{}, {}".format(ops[0],ops[1]))
    reg[ops[0]]>>=ops[1]

  elif operation == 28: # EXIT
    WriteDebug("EXIT {}".format(ops[0]))
    exit_code=ops[0]
    running=False

  elif operation == 29: # PRINTLN
    s=getString(ops[0])
    WriteDebug('PRINTLN {} ("{}")'.format(ops[0],s))
    print(s)
    sys.stdout.flush()

  elif operation == 30: # PRINT
    s=getString(ops[0])
    WriteDebug('PRINT {} ("{}")'.format(ops[0],s))
    print(s,end="")
    sys.stdout.flush()

  elif operation == 31: # RUN
    s=getString(ops[0])
    WriteDebug('run {} ("{}")'.format(ops[0],s))
    os.system(s)

  else:
    WriteDebug("Unsupported op={} @ pc={}".format(op,pc))
    running=False

sys.exit(exit_code)
