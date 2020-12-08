#!/usr/bin/env bash
# -*- mode: bash; tab-width: 2; indent-tabs-mode: nil; -*-
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

# Define the BS VM program. We use a packed string (3 characters per 2 bytes).
p="DON'T MODIFY THIS LINE! IT IS REPLACED BY THE BUILD PROCESS!"

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
nout=(0 1 1 1 0 0 0 0 0 0 0 0 0 0 0 0 0 1 1 1 1 1 1 1 1 1 1 1 0 0 0 0)
ninr=(0 0 1 1 2 2 0 0 0 0 0 0 0 0 0 1 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0)
ninx=(0 1 1 1 1 1 1 1 0 1 1 1 1 1 1 1 1 0 1 1 1 1 1 1 1 1 1 1 1 1 1 1)

# Helper functions.
ord() { LC_CTYPE=C printf '%d' "'$1"; }

WriteDebug() { >&2 echo "DEBUG: $1"; }

getS() {
  # Read the string length (32-bit integer).
  a=$1
  b0=${m[$a]}; b1=${m[$((a+1))]}; b2=${m[$((a+2))]}; b3=${m[$((a+3))]}
  l=$((b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)))

  # Extract the string from memory.
  a=$((a+3))
  str=""
  for i in $(seq 1 $l); do
    c=${m[$((a+i))]}
    str+=$(printf "\x$(printf %x $c)")
  done
}

# Note: We leave the memory empty and rely on well-behaving code (i.e. that
# does not read undefined values).

# Clear execution state.
pc=0
pc0=0
cc=0
for i in $(seq 0 255); do r[$i]=0; done

# Convert the packed string to bytes and store it in the memory.
v=$(echo "$p" | awk '{print length}')
v=$(((v*2)/3))
WriteDebug "prg_size=$v"
for i in $(seq 0 $(((v-1)/2))); do
  c1=$(($(ord "${p:$((i*3)):1}")-40))   # 6 bits (0-63)
  c2=$(($(ord "${p:$((i*3+1)):1}")-40)) # 5 bits (0-31)
  c3=$(($(ord "${p:$((i*3+2)):1}")-40)) # 5 bits (0-31)
  b1=$(((c1<<2)|(c2>>3)))
  b2=$((((c2&7)<<5)|c3))
  m[$((i*2))]=$b1
  m[$((i*2+1))]=$b2
  WriteDebug "(c1,c2,c3)=($c1,$c2,$c3) -> ($b1,$b2)"
done

# Main execution loop.
exit_code=1
running=1
while [ $running -eq 1 ]; do
  # Read the next opcode.
  pc0=$pc
  op0=${m[pc]}
  pc=$((pc+1))

  # Decode the opcode:
  #   Bits 0-5: operation
  #   Bits 6-7: argument type
  at=$((op0>>6))
  op=$((op0&63))

  WriteDebug "PC=$pc0 CC=$cc OP=$op0 OP*=$op AT=$at"

  # Read the operands.
  o=()
  k=0
  n=${nout[$op]}
  while [ $k -lt $n ]; do
    # Get register number (0-255)
    o+=(${m[$pc]})
    pc=$((pc+1))
    k=$((k+1))
  done
  n=$((k+${ninr[$op]}))
  while [ $k -lt $n ]; do
    # Get register value
    o+=(${r[${m[$pc]}]})
    pc=$((pc+1))
    k=$((k+1))
  done
  n=$((k+${ninx[$op]}))
  while [ $k -lt $n ]; do
    if [ $at -eq 3 ]; then
      # 32-bit immediate.
      b0=${m[$pc]}; b1=${m[$((pc+1))]}; b2=${m[$((pc+2))]}; b3=${m[$((pc+3))]}
      v=$((b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)))
      pc=$((pc+4))
    else
      # Arg types 0-2 use a single byte.
      v=${m[$pc]}
      pc=$((pc+1))

      if [ $at -eq 0 ]; then
        # Register value.
        v=${r[$v]}
      else
        # Convert unsigned to signed byte (-128..127).
        if [ $v -gt 127 ]; then v=$((v - 256)); fi

        if [ $at -eq 2 ]; then
          # 8-bit PC-relative offset.
          v=$((pc0 + v))
        fi
        # else v=$v (at=1, 8-bit signed immedate)
      fi
    fi
    o+=($v)
    k=$((k+1))
  done

  # Execute the instruction.
  case $op in
    1) # MOV
      WriteDebug "MOV R${o[0]}, ${o[1]}"
      r[${o[0]}]=${o[1]}
      ;;

    2) # LDB
      WriteDebug "LDB R${o[0]}, ${o[1]}, ${o[2]}"
      r[${o[0]}]=${m[$((${o[1]}+${o[2]}))]}
      ;;

    3) # LDW
      WriteDebug "LDW R${o[0]}, ${o[1]}, ${o[2]}"
      a=$((${o[1]}+${o[2]}))
      b0=${m[$a]}; b1=${m[$((a+1))]}; b2=${m[$((a+2))]}; b3=${m[$((a+3))]}
      r[${o[0]}]=$((b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)))
      ;;

    4) # STB
      WriteDebug "STB ${o[0]}, ${o[1]}, ${o[2]}"
      m[$((${o[1]}+${o[2]}))]=$((${o[0]} & 255))
      ;;

    5) # STW
      WriteDebug "STW ${o[0]}, ${o[1]}, ${o[2]}"
      a=$((${o[1]}+${o[2]}))
      v=${o[0]}
      m[$a]=$((v & 255))
      m[$((a+1))]=$(((v >> 8) & 255))
      m[$((a+2))]=$(((v >> 16) & 255))
      m[$((a+3))]=$(((v >> 24) & 255))
      ;;

    6) # JMP
      WriteDebug "JMP ${o[0]}"
      pc=${o[0]}
      ;;

    7) # JSR
      WriteDebug "JSR ${o[0]}"
      r[255]=$((${r[255]} - 4)) # Pre-decrement SP
      a=${r[255]}
      m[$a]=$((pc & 255))
      m[$((a+1))]=$(((pc >> 8) & 255))
      m[$((a+2))]=$(((pc >> 16) & 255))
      m[$((a+3))]=$(((pc >> 24) & 255))
      pc=${o[0]}
      ;;

    8) # RTS
      WriteDebug "RTS"
      a=${r[255]}
      b0=${m[$a]}; b1=${m[$((a+1))]}; b2=${m[$((a+2))]}; b3=${m[$((a+3))]}
      pc=$((b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)))
      r[255]=$((${r[255]} + 4)) # Post-increment SP
      ;;

    9) # BEQ
      WriteDebug "BEQ ${o[0]}"
      if [ $((cc & _EQ)) -ne 0 ]; then pc=${o[0]}; fi
      ;;

    10) # BNE
      WriteDebug "BNE ${o[0]}"
      if [ $((cc & _EQ)) -eq 0 ]; then pc=${o[0]}; fi
      ;;

    11) # BLT
      WriteDebug "BLT ${o[0]}"
      if [ $((cc & _LT)) -ne 0 ]; then pc=${o[0]}; fi
      ;;

    12) # BLE
      WriteDebug "BLE ${o[0]}"
      if [ $((cc & _LT)) -ne 0 -or $((cc & _EQ)) -ne 0 ]; then pc=${o[0]}; fi
      ;;

    13) # BGT
      WriteDebug "BGT ${o[0]}"
      if [ $((cc & _GT)) -ne 0 ]; then pc=${o[0]}; fi
      ;;

    14) # BGE
      WriteDebug "BGE ${o[0]}"
      if [ $((cc & _GT)) -ne 0 -or $((cc & _EQ)) -ne 0 ]; then pc=${o[0]}; fi
      ;;

    15) # CMP
      WriteDebug "CMP ${o[0]}, ${o[1]}"
      cc=0
      if [ ${o[0]} -eq ${o[1]} ]; then cc=$((cc | _EQ)); fi
      if [ ${o[0]} -lt ${o[1]} ]; then cc=$((cc | _LT)); fi
      if [ ${o[0]} -gt ${o[1]} ]; then cc=$((cc | _GT)); fi
      ;;

    16) # PUSH
      WriteDebug "PUSH ${o[0]}"
      r[255]=$((${r[255]} - 4)) # Pre-decrement SP
      a=${r[255]}
      v=${o[0]}
      m[$a]=$((v & 255))
      m[$((a+1))]=$(((v >> 8) & 255))
      m[$((a+2))]=$(((v >> 16) & 255))
      m[$((a+3))]=$(((v >> 24) & 255))
      ;;

    17) # POP
      WriteDebug "POP R${o[0]}"
      a=${r[255]}
      b0=${m[$a]}; b1=${m[$((a+1))]}; b2=${m[$((a+2))]}; b3=${m[$((a+3))]}
      r[${o[0]}]=$((b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)))
      r[255]=$((${r[255]} + 4)) # Post-increment SP
      ;;

    18) # ADD
      WriteDebug "ADD R${o[0]}, ${o[1]}"
      r[${o[0]}]=$((${r[${o[0]}]} + ${o[1]}))
      ;;

    19) # SUB
      WriteDebug "SUB R${o[0]}, ${o[1]}"
      r[${o[0]}]=$((${r[${o[0]}]} - ${o[1]}))
      ;;

    20) # MUL
      WriteDebug "MUL R${o[0]}, ${o[1]}"
      r[${o[0]}]=$((${r[${o[0]}]} * ${o[1]}))
      ;;

    21) # DIV
      WriteDebug "DIV R${o[0]}, ${o[1]}"
      r[${o[0]}]=$((${r[${o[0]}]} / ${o[1]}))
      ;;

    22) # MOD
      WriteDebug "MOD R${o[0]}, ${o[1]}"
      r[${o[0]}]=$((${r[${o[0]}]} % ${o[1]}))
      ;;

    23) # AND
      WriteDebug "AND R${o[0]}, ${o[1]}"
      r[${o[0]}]=$((${r[${o[0]}]} & ${o[1]}))
      ;;

    24) # OR
      WriteDebug "OR R${o[0]}, ${o[1]}"
      r[${o[0]}]=$((${r[${o[0]}]} | ${o[1]}))
      ;;

    25) # XOR
      WriteDebug "XOR R${o[0]}, ${o[1]}"
      r[${o[0]}]=$((${r[${o[0]}]} ^ ${o[1]}))
      ;;

    26) # SHL
      WriteDebug "SHL R${o[0]}, ${o[1]}"
      r[${o[0]}]=$((${r[${o[0]}]} << ${o[1]}))
      ;;

    27) # SHR
      WriteDebug "SHR R${o[0]}, ${o[1]}"
      r[${o[0]}]=$((${r[${o[0]}]} >> ${o[1]}))
      ;;

    28) # EXIT
      WriteDebug "EXIT ${o[0]}"
      exit_code=${o[0]}
      running=0
      ;;

    29) # PRINTLN
      getS ${o[0]}
      WriteDebug "PRINTLN ${o[0]} ($str)"
      printf "$str\n"
      ;;

    30) # PRINT
      getS ${o[0]}
      WriteDebug "PRINT ${o[0]} ($str)"
      printf "$str"
      ;;

    31) # RUN
      getS ${o[0]}
      WriteDebug "RUN ${o[0]} ($str)"
      eval "$str"
      ;;

    *)
      WriteDebug "Unsupported op=$op @ pc=$pc"
      running=0
      ;;
  esac
done

exit $exit_code
