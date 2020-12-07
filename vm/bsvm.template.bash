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
prg="DON'T MODIFY THIS LINE! IT IS REPLACED BY THE BUILD PROCESS!"

# Helper functions.
ord() { LC_CTYPE=C printf '%d' "'$1"; }

WriteDebug() { >&2 echo "DEBUG: $1"; }

getString() {
  # Read the string length (32-bit integer).
  a=$1
  b0=${ram[$a]}; b1=${ram[$((a+1))]}; b2=${ram[$((a+2))]}; b3=${ram[$((a+3))]}
  l=$((b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)))

  # Extract the string from memory.
  a=$((a+3))
  str=""
  for i in $(seq 1 $l); do
    c=${ram[$((a+i))]}
    str+=$(printf "\x$(printf %x $c)")
  done
}

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

# Create RAM.
# Note: We leave the RAM empty and rely on well-behaving code (i.e. that
# does not read undefined values).
ram=()

# Clear execution state.
pc=0
instrPC=0
cc=0
reg=()
for i in $(seq 0 255); do reg[$i]=0; done

# Convert the packed string to bytes and store it in the RAM.
prg_size=$(echo "$prg" | awk '{print length}')
prg_size=$(((prg_size * 2) / 3))
WriteDebug "prg_size=$prg_size"
for i in $(seq 0 $(((prg_size - 1)/2))); do
  c1=$(($(ord "${prg:$((i*3)):1}")-40))   # 6 bits (0-63)
  c2=$(($(ord "${prg:$((i*3+1)):1}")-40)) # 5 bits (0-31)
  c3=$(($(ord "${prg:$((i*3+2)):1}")-40)) # 5 bits (0-31)
  b1=$(((c1 << 2) | (c2 >> 3)))
  b2=$((((c2 & 7) << 5) | c3))
  ram[$((i*2))]=$b1
  ram[$((i*2+1))]=$b2
  WriteDebug "(c1,c2,c3)=($c1,$c2,$c3) -> ($b1,$b2)"
done

# Main execution loop.
exit_code=1
running=1
while [ $running -eq 1 ]; do
  # Read the next opcode.
  instrPC=$pc
  op=${ram[pc]}
  pc=$((pc+1))

  # Decode the opcode:
  #   Bits 0-5: operation
  #   Bits 6-7: argument type
  arg_type=$((op >> 6))
  operation=$((op & 63))

  WriteDebug "PC=$instrPC CC=$cc OP=$op OP*=$operation AT=$arg_type"

  # Read the operands.
  ops=()
  k=0
  n=${nout[$operation]}
  while [ $k -lt $n ]; do
    # Get register number (0-255)
    ops+=(${ram[$pc]})
    pc=$((pc+1))
    k=$((k+1))
  done
  n=$((k+${ninr[$operation]}))
  while [ $k -lt $n ]; do
    # Get register value
    ops+=(${reg[${ram[$pc]}]})
    pc=$((pc+1))
    k=$((k+1))
  done
  n=$((k+${ninx[$operation]}))
  while [ $k -lt $n ]; do
    if [ $arg_type -eq 3 ]; then
      # 32-bit immediate.
      b0=${ram[$pc]}; b1=${ram[$((pc+1))]}; b2=${ram[$((pc+2))]}; b3=${ram[$((pc+3))]}
      v=$((b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)))
      pc=$((pc+4))
    else
      # Arg types 0-2 use a single byte.
      v=${ram[$pc]}
      pc=$((pc+1))

      if [ $arg_type -eq 0 ]; then
        # Register value.
        v=${reg[$v]}
      else
        # Convert unsigned to signed byte (-128..127).
        if [ $v -gt 127 ]; then v=$((v - 256)); fi

        if [ $arg_type -eq 2 ]; then
          # 8-bit PC-relative offset.
          v=$((instrPC + v))
        fi
        # else v=$v (arg_type=1, 8-bit signed immedate)
      fi
    fi
    ops+=($v)
    k=$((k+1))
  done

  # Execute the instruction.
  case $operation in
    1) # MOV
      WriteDebug "MOV R${ops[0]}, ${ops[1]}"
      reg[${ops[0]}]=${ops[1]}
      ;;

    2) # LDB
      WriteDebug "LDB R${ops[0]}, ${ops[1]}, ${ops[2]}"
      reg[${ops[0]}]=${ram[$((${ops[1]}+${ops[2]}))]}
      ;;

    3) # LDW
      WriteDebug "LDW R${ops[0]}, ${ops[1]}, ${ops[2]}"
      a=$((${ops[1]}+${ops[2]}))
      b0=${ram[$a]}; b1=${ram[$((a+1))]}; b2=${ram[$((a+2))]}; b3=${ram[$((a+3))]}
      reg[${ops[0]}]=$((b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)))
      ;;

    4) # STB
      WriteDebug "STB ${ops[0]}, ${ops[1]}, ${ops[2]}"
      ram[$((${ops[1]}+${ops[2]}))]=$((${ops[0]} & 255))
      ;;

    5) # STW
      WriteDebug "STW ${ops[0]}, ${ops[1]}, ${ops[2]}"
      a=$((${ops[1]}+${ops[2]}))
      v=${ops[0]}
      ram[$a]=$((v & 255))
      ram[$((a+1))]=$(((v >> 8) & 255))
      ram[$((a+2))]=$(((v >> 16) & 255))
      ram[$((a+3))]=$(((v >> 24) & 255))
      ;;

    6) # JMP
      WriteDebug "JMP ${ops[0]}"
      pc=${ops[0]}
      ;;

    7) # JSR
      WriteDebug "JSR ${ops[0]}"
      reg[255]=$((${reg[255]} - 4)) # Pre-decrement SP
      a=${reg[255]}
      ram[$a]=$((pc & 255))
      ram[$((a+1))]=$(((pc >> 8) & 255))
      ram[$((a+2))]=$(((pc >> 16) & 255))
      ram[$((a+3))]=$(((pc >> 24) & 255))
      pc=${ops[0]}
      ;;

    8) # RTS
      WriteDebug "RTS"
      a=${reg[255]}
      b0=${ram[$a]}; b1=${ram[$((a+1))]}; b2=${ram[$((a+2))]}; b3=${ram[$((a+3))]}
      pc=$((b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)))
      reg[255]=$((${reg[255]} + 4)) # Post-increment SP
      ;;

    9) # BEQ
      WriteDebug "BEQ ${ops[0]}"
      if [ $((cc & _EQ)) -ne 0 ]; then pc=${ops[0]}; fi
      ;;

    10) # BNE
      WriteDebug "BNE ${ops[0]}"
      if [ $((cc & _EQ)) -eq 0 ]; then pc=${ops[0]}; fi
      ;;

    11) # BLT
      WriteDebug "BLT ${ops[0]}"
      if [ $((cc & _LT)) -ne 0 ]; then pc=${ops[0]}; fi
      ;;

    12) # BLE
      WriteDebug "BLE ${ops[0]}"
      if [ $((cc & _LT)) -ne 0 -or $((cc & _EQ)) -ne 0 ]; then pc=${ops[0]}; fi
      ;;

    13) # BGT
      WriteDebug "BGT ${ops[0]}"
      if [ $((cc & _GT)) -ne 0 ]; then pc=${ops[0]}; fi
      ;;

    14) # BGE
      WriteDebug "BGE ${ops[0]}"
      if [ $((cc & _GT)) -ne 0 -or $((cc & _EQ)) -ne 0 ]; then pc=${ops[0]}; fi
      ;;

    15) # CMP
      WriteDebug "CMP ${ops[0]}, ${ops[1]}"
      cc=0
      if [ ${ops[0]} -eq ${ops[1]} ]; then cc=$((cc | _EQ)); fi
      if [ ${ops[0]} -lt ${ops[1]} ]; then cc=$((cc | _LT)); fi
      if [ ${ops[0]} -gt ${ops[1]} ]; then cc=$((cc | _GT)); fi
      ;;

    16) # PUSH
      WriteDebug "PUSH ${ops[0]}"
      reg[255]=$((${reg[255]} - 4)) # Pre-decrement SP
      a=${reg[255]}
      v=${ops[0]}
      ram[$a]=$((v & 255))
      ram[$((a+1))]=$(((v >> 8) & 255))
      ram[$((a+2))]=$(((v >> 16) & 255))
      ram[$((a+3))]=$(((v >> 24) & 255))
      ;;

    17) # POP
      WriteDebug "POP R${ops[0]}"
      a=${reg[255]}
      b0=${ram[$a]}; b1=${ram[$((a+1))]}; b2=${ram[$((a+2))]}; b3=${ram[$((a+3))]}
      reg[${ops[0]}]=$((b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)))
      reg[255]=$((${reg[255]} + 4)) # Post-increment SP
      ;;

    18) # ADD
      WriteDebug "ADD R${ops[0]}, ${ops[1]}"
      reg[${ops[0]}]=$((${reg[${ops[0]}]} + ${ops[1]}))
      ;;

    19) # SUB
      WriteDebug "SUB R${ops[0]}, ${ops[1]}"
      reg[${ops[0]}]=$((${reg[${ops[0]}]} - ${ops[1]}))
      ;;

    20) # MUL
      WriteDebug "MUL R${ops[0]}, ${ops[1]}"
      reg[${ops[0]}]=$((${reg[${ops[0]}]} * ${ops[1]}))
      ;;

    21) # DIV
      WriteDebug "DIV R${ops[0]}, ${ops[1]}"
      reg[${ops[0]}]=$((${reg[${ops[0]}]} / ${ops[1]}))
      ;;

    22) # MOD
      WriteDebug "MOD R${ops[0]}, ${ops[1]}"
      reg[${ops[0]}]=$((${reg[${ops[0]}]} % ${ops[1]}))
      ;;

    23) # AND
      WriteDebug "AND R${ops[0]}, ${ops[1]}"
      reg[${ops[0]}]=$((${reg[${ops[0]}]} & ${ops[1]}))
      ;;

    24) # OR
      WriteDebug "OR R${ops[0]}, ${ops[1]}"
      reg[${ops[0]}]=$((${reg[${ops[0]}]} | ${ops[1]}))
      ;;

    25) # XOR
      WriteDebug "XOR R${ops[0]}, ${ops[1]}"
      reg[${ops[0]}]=$((${reg[${ops[0]}]} ^ ${ops[1]}))
      ;;

    26) # SHL
      WriteDebug "SHL R${ops[0]}, ${ops[1]}"
      reg[${ops[0]}]=$((${reg[${ops[0]}]} << ${ops[1]}))
      ;;

    27) # SHR
      WriteDebug "SHR R${ops[0]}, ${ops[1]}"
      reg[${ops[0]}]=$((${reg[${ops[0]}]} >> ${ops[1]}))
      ;;

    28) # EXIT
      WriteDebug "EXIT ${ops[0]}"
      exit_code=${ops[0]}
      running=0
      ;;

    29) # PRINTLN
      getString ${ops[0]}
      WriteDebug "PRINTLN ${ops[0]} ($str)"
      printf "$str\n"
      ;;

    30) # PRINT
      getString ${ops[0]}
      WriteDebug "PRINT ${ops[0]} ($str)"
      printf "$str"
      ;;

    31) # RUN
      getString ${ops[0]}
      WriteDebug "RUN ${ops[0]} ($str)"
      eval "$str"
      ;;

    *)
      WriteDebug "Unsupported op=$op @ pc=$pc"
      running=0
      ;;
  esac
done

exit $exit_code
