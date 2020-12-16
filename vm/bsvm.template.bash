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
p='?((((('  # DON'T MODIFY THIS LINE! IT IS REPLACED BY THE BUILD PROCESS!

# Detect if we're running on Bash or zsh (we use $_B here and there to handle differences).
[ -n "$BASH" ] && _B=0

# Constants.
_EQ=1
_LT=2
_LE=3 # _LT | _EQ
_GT=4
_GE=5 # _GT | _EQ

# Instruction operand configuration (one element per instruction).
#
#  * nout - Number of output (or in/out) register operands.
#  * ninr - Number of input register operands.
#  * ninx - Number of "final" input operands (any operand kind).
#
# OP:                       1 1 1 1 1 1 1 1 1 1 2 2 2 2 2 2 2 2 2 2 3 3
#     (0) 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
nout=($_B 1 1 1 0 0 0 0 0 0 0 0 0 0 0 0 0 1 1 1 1 1 1 1 1 1 1 1 0 0 0 0)
ninr=($_B 0 1 1 2 2 0 0 0 0 0 0 0 0 0 1 0 0 0 0 0 0 0 0 0 0 0 0 0 1 1 1)
ninx=($_B 1 1 1 1 1 1 1 0 1 1 1 1 1 1 1 1 0 1 1 1 1 1 1 1 1 1 1 1 1 1 1)

# Helper functions.
WriteDebug(){ >&2 echo "DEBUG: $1"; }

getS(){
  # Extract the string from memory.
  a=$1
  str=""
  for i in $(seq 1 $2);do
    c=${m[$((a+i-1))]}
    str+=$(printf "\x$(printf %x $c)")
  done
}

# Note: We leave the memory empty and rely on well-behaving code (i.e. that
# does not read undefined values).

# Clear execution state.
pc=1
cc=0

# Convert the packed string to bytes and store it in the memory.
v=$((($(echo "$p"|awk '{print length}')*2)/3))
WriteDebug "prg_size=$v"
for i in $(seq 0 $(((v-1)/2)));do
  # Convert three consecutive characters to an array of ASCII codes.
  x="${p:$((i*3)):3}"
  LC_CTYPE=C printf -v x '%d %d %d' "'${x:0:1}" "'${x:1:1}" "'${x:2:1}"
  [ -n "$_B" ] && x=(0 $x) || x=("${(s: :)x}")

  # Convert the three ASCII codes to two full-range (0-255) bytes.
  c1=$((${x[1]}-40))   # 6 bits (0-63)
  c2=$((${x[2]}-40))   # 5 bits (0-31)
  c3=$((${x[3]}-40))   # 5 bits (0-31)
  b1=$(((c1<<2)|(c2>>3)))
  b2=$((((c2&7)<<5)|c3))
  m[$((i*2+1))]=$b1
  m[$((i*2+2))]=$b2
  WriteDebug "(c1,c2,c3)=($c1,$c2,$c3) -> ($b1,$b2)"
done

# Main execution loop.
exit_code=1
running=1
while [ $running -eq 1 ];do
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
  o=($_B)
  if [ ${nout[$op]} = 1 ];then
    # Get register number (0-255)
    o+=(${m[$pc]})
    pc=$((pc+1))
  fi
  n=$((pc+${ninr[$op]}))
  while [ $pc -lt $n ];do
    # Get register value
    o+=(${r[${m[$pc]}]})
    pc=$((pc+1))
  done
  if [ ${ninx[$op]} = 1 ];then
    if [ $at = 3 ];then
      # 32-bit immediate.
      b0=${m[$pc]}
      b1=${m[$((pc+1))]}
      b2=${m[$((pc+2))]}
      b3=${m[$((pc+3))]}
      v=$((b0|(b1<<8)|(b2<<16)|(b3<<24)))
      pc=$((pc+4))
    else
      # Arg types 0-2 use a single byte.
      v=${m[$pc]}
      pc=$((pc+1))

      if [ $at = 0 ];then
        # Register value.
        v=${r[$v]}
      else
        # Convert unsigned to signed byte (-128..127).
        [ $v -gt 127 ] && v=$((v-256))

        [ $at = 2 ] && v=$((pc0+v)) # 8-bit PC-relative offset.
        # else v=$v (at=1, 8-bit signed immedate)
      fi
    fi
    o+=($v)
  fi

  # Execute the instruction.
  case $op in
    1) # MOV
      WriteDebug "MOV R${o[1]}, ${o[2]}"
      r[${o[1]}]=${o[2]}
      ;;

    2) # LDB
      WriteDebug "LDB R${o[1]}, ${o[2]}, ${o[3]}"
      r[${o[1]}]=${m[$((${o[2]}+${o[3]}))]}
      ;;

    3) # LDW
      WriteDebug "LDW R${o[1]}, ${o[2]}, ${o[3]}"
      a=$((${o[2]}+${o[3]}))
      b0=${m[$a]}
      b1=${m[$((a+1))]}
      b2=${m[$((a+2))]}
      b3=${m[$((a+3))]}
      r[${o[1]}]=$((b0|(b1<<8)|(b2<<16)|(b3<<24)))
      ;;

    4) # STB
      WriteDebug "STB ${o[1]}, ${o[2]}, ${o[3]}"
      m[$((${o[2]}+${o[3]}))]=$((${o[1]}&255))
      ;;

    5) # STW
      WriteDebug "STW ${o[1]}, ${o[2]}, ${o[3]}"
      a=$((${o[2]}+${o[3]}))
      v=${o[1]}
      m[$a]=$((v&255))
      m[$((a+1))]=$(((v>>8)&255))
      m[$((a+2))]=$(((v>>16)&255))
      m[$((a+3))]=$(((v>>24)&255))
      ;;

    6) # JMP
      WriteDebug "JMP ${o[1]}"
      pc=${o[1]}
      ;;

    7) # JSR
      WriteDebug "JSR ${o[1]}"
      r[255]=$((${r[255]}-4)) # Pre-decrement SP
      a=${r[255]}
      m[$a]=$((pc&255))
      m[$((a+1))]=$(((pc>>8)&255))
      m[$((a+2))]=$(((pc>>16)&255))
      m[$((a+3))]=$(((pc>>24)&255))
      pc=${o[1]}
      ;;

    8) # RTS
      WriteDebug "RTS"
      a=${r[255]}
      b0=${m[$a]}
      b1=${m[$((a+1))]}
      b2=${m[$((a+2))]}
      b3=${m[$((a+3))]}
      pc=$((b0|(b1<<8)|(b2<<16)|(b3<<24)))
      r[255]=$((${r[255]}+4)) # Post-increment SP
      ;;

    9) # BEQ
      WriteDebug "BEQ ${o[1]}"
      [ $((cc&_EQ)) -ne 0 ] && pc=${o[1]}
      ;;

    10) # BNE
      WriteDebug "BNE ${o[1]}"
      [ $((cc&_EQ)) -eq 0 ] && pc=${o[1]}
      ;;

    11) # BLT
      WriteDebug "BLT ${o[1]}"
      [ $((cc&_LT)) -ne 0 ] && pc=${o[1]}
      ;;

    12) # BLE
      WriteDebug "BLE ${o[1]}"
      [ $((cc&_LE)) -ne 0 ] && pc=${o[1]}
      ;;

    13) # BGT
      WriteDebug "BGT ${o[1]}"
      [ $((cc&_GT)) -ne 0 ] && pc=${o[1]}
      ;;

    14) # BGE
      WriteDebug "BGE ${o[1]}"
      [ $((cc&_GE)) -ne 0 ] && pc=${o[1]}
      ;;

    15) # CMP
      WriteDebug "CMP ${o[1]}, ${o[2]}"
      cc=0
      [ ${o[1]} -eq ${o[2]} ] && cc=_EQ
      [ ${o[1]} -lt ${o[2]} ] && cc=$((cc|_LT))
      [ ${o[1]} -gt ${o[2]} ] && cc=$((cc|_GT))
      ;;

    16) # PUSH
      WriteDebug "PUSH ${o[1]}"
      r[255]=$((${r[255]}-4)) # Pre-decrement SP
      a=${r[255]}
      v=${o[1]}
      m[$a]=$((v&255))
      m[$((a+1))]=$(((v>>8)&255))
      m[$((a+2))]=$(((v>>16)&255))
      m[$((a+3))]=$(((v>>24)&255))
      ;;

    17) # POP
      WriteDebug "POP R${o[1]}"
      a=${r[255]}
      b0=${m[$a]}
      b1=${m[$((a+1))]}
      b2=${m[$((a+2))]}
      b3=${m[$((a+3))]}
      r[${o[1]}]=$((b0|(b1<<8)|(b2<<16)|(b3<<24)))
      r[255]=$((${r[255]}+4)) # Post-increment SP
      ;;

    18) # ADD
      WriteDebug "ADD R${o[1]}, ${o[2]}"
      r[${o[1]}]=$((${r[${o[1]}]}+${o[2]}))
      ;;

    19) # SUB
      WriteDebug "SUB R${o[1]}, ${o[2]}"
      r[${o[1]}]=$((${r[${o[1]}]}-${o[2]}))
      ;;

    20) # MUL
      WriteDebug "MUL R${o[1]}, ${o[2]}"
      r[${o[1]}]=$((${r[${o[1]}]}*${o[2]}))
      ;;

    21) # DIV
      WriteDebug "DIV R${o[1]}, ${o[2]}"
      r[${o[1]}]=$((${r[${o[1]}]}/${o[2]}))
      ;;

    22) # MOD
      WriteDebug "MOD R${o[1]}, ${o[2]}"
      r[${o[1]}]=$((${r[${o[1]}]}%${o[2]}))
      ;;

    23) # AND
      WriteDebug "AND R${o[1]}, ${o[2]}"
      r[${o[1]}]=$((${r[${o[1]}]}&${o[2]}))
      ;;

    24) # OR
      WriteDebug "OR R${o[1]}, ${o[2]}"
      r[${o[1]}]=$((${r[${o[1]}]}|${o[2]}))
      ;;

    25) # XOR
      WriteDebug "XOR R${o[1]}, ${o[2]}"
      r[${o[1]}]=$((${r[${o[1]}]}^${o[2]}))
      ;;

    26) # SHL
      WriteDebug "SHL R${o[1]}, ${o[2]}"
      r[${o[1]}]=$((${r[${o[1]}]}<<${o[2]}))
      ;;

    27) # SHR
      WriteDebug "SHR R${o[1]}, ${o[2]}"
      r[${o[1]}]=$((${r[${o[1]}]}>>${o[2]}))
      ;;

    28) # EXIT
      WriteDebug "EXIT ${o[1]}"
      exit_code=${o[1]}
      running=0
      ;;

    29) # PRINTLN
      getS ${o[1]} ${o[2]}
      WriteDebug "PRINTLN ${o[1]} ${o[2]} ($str)"
      printf "$str\n"
      ;;

    30) # PRINT
      getS ${o[1]} ${o[2]}
      WriteDebug "PRINT ${o[1]} ${o[2]} ($str)"
      printf "$str"
      ;;

    31) # RUN
      getS ${o[1]} ${o[2]}
      WriteDebug "RUN ${o[1]} ${o[2]} ($str)"
      eval "$str"
      ;;

    *)
      WriteDebug "Unsupported op=$op @ pc=$pc"
      running=0
      ;;
  esac
done

exit $exit_code
