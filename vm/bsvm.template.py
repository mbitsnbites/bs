#!/usr/bin/env python3
# -*- mode: python; tab-width: 4; indent-tabs-mode: t; -*-
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
import array,codecs,os,struct,sys

# Ensure that we use UTF-8 encoding for stdout.
sys.stdout=codecs.getwriter("utf8")(sys.stdout.detach() if sys.version_info[0]>=3 else sys.stdout)

# Define the BS VM program. We use a packed string (3 characters per 2 bytes).
p="?((((("  # DON'T MODIFY THIS LINE! IT IS REPLACED BY THE BUILD PROCESS!

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
ninr=[0,0,1,1,2,2,0,0,0,0,0,0,0,0,0,1,0,0,0,0,0,0,0,0,0,0,0,0,0,1,1,1]
ninx=[0,1,1,1,1,1,1,1,0,1,1,1,1,1,1,1,1,0,1,1,1,1,1,1,1,1,1,1,1,1,1,1]

# Helper functions.
def WriteDebug(s):
	print("DEBUG: " + s, file=sys.stderr)

def getI(a):
	return struct.unpack_from("<l",m,a)[0]

def setI(a,v):
	struct.pack_into("<l",m,a,v)

def getS(a,l):
	# Extract the string from memory.
	return m[a:(a+l)].decode("utf8")

# Create RAM.
m=bytearray(1<<20)

# Clear execution state.
pc=1
cc=0
r=array.array('l',(0 for i in range(0,256)))

# Convert the packed string to bytes and store it in the memory.
v=(len(p)*2)//3
WriteDebug("prg_size={}".format(v))
for i in range(0,v//2):
	c1=ord(p[i*3])-40    # 6 bits (0-63)
	c2=ord(p[i*3+1])-40  # 5 bits (0-31)
	c3=ord(p[i*3+2])-40  # 5 bits (0-31)
	b1=(c1<<2)|(c2>>3)
	b2=((c2&7)<<5)|c3
	m[i*2+1]=b1
	m[i*2+2]=b2
	WriteDebug("(c1,c2,c3)=({},{},{}) -> ({},{})".format(c1,c2,c3,b1,b2))

# Main execution loop.
exit_code=1
running=True
while running:
	# Read the next opcode.
	pc0=pc
	op0=m[pc]
	pc+=1

	# Decode the opcode:
	#   Bits 0-5: operation
	#   Bits 6-7: argument type
	at=op0>>6
	op=op0&63

	WriteDebug("PC={} CC={} OP={} OP*={} AT={}".format(pc0,cc,op0,op,at))

	# Read the operands.
	o=[]
	for i in range(nout[op]):
		# Get register number (0-255)
		o+=[m[pc]]
		pc+=1
	for i in range(ninr[op]):
		# Get register value
		o+=[r[m[pc]]]
		pc+=1
	for i in range(ninx[op]):
		if at == 3:
			# 32-bit immediate.
			v=getI(pc)
			pc+=4
		else:
			# Arg types 0-2 use a single byte.
			v=m[pc]
			pc+=1

			if at == 0:
				# Register value.
				v=r[v]
			else:
				# Convert unsigned to signed byte (-128..127).
				if v > 127:
					v-=256

				if at == 2:
					# 8-bit PC-relative offset.
					v+=pc0
				# else v=v (at=1, 8-bit signed immedate)
		o+=[v]

	# Execute the instruction.
	if op == 1: # MOV
		WriteDebug("MOV R{}, {}".format(o[0],o[1]))
		r[o[0]]=o[1]

	elif op == 2: # LDB
		WriteDebug("LDB R{}, {}, {}".format(o[0],o[1],o[2]))
		r[o[0]]=m[o[1]+o[2]]

	elif op == 3: # LDW
		WriteDebug("LDW R{}, {}, {}".format(o[0],o[1],o[2]))
		r[o[0]]=getI(o[1]+o[2])


	elif op == 4: # STB
		WriteDebug("STB {}, {}, {}".format(o[0],o[1],o[2]))
		m[o[1]+o[2]]=o[0]&255

	elif op == 5: # STW
		WriteDebug("STW {}, {}, {}".format(o[0],o[1],o[2]))
		setI(o[1]+o[2],o[0])

	elif op == 6: # JMP
		WriteDebug("JMP {}".format(o[0]))
		pc=o[0]

	elif op == 7: # JSR
		WriteDebug("JSR {}".format(o[0]))
		r[255]-=4  # Pre-decrement SP
		setI(r[255],pc)
		pc=o[0]

	elif op == 8: # RTS
		WriteDebug("RTS")
		pc=getI(r[255])
		r[255]+=4  # Post-increment SP

	elif op == 9: # BEQ
		WriteDebug("BEQ {}".format(o[0]))
		if cc & _EQ != 0:
			pc=o[0]

	elif op == 10: # BNE
		WriteDebug("BNE {}".format(o[0]))
		if cc & _EQ == 0:
			pc=o[0]

	elif op == 11: # BLT
		WriteDebug("BLT {}".format(o[0]))
		if cc & _LT != 0:
			pc=o[0]

	elif op == 12: # BLE
		WriteDebug("BLE {}".format(o[0]))
		if cc & (_LT|_EQ) != 0:
			pc=o[0]

	elif op == 13: # BGT
		WriteDebug("BGT {}".format(o[0]))
		if cc & _GT != 0:
			pc=o[0]

	elif op == 14: # BGE
		WriteDebug("BGE {}".format(o[0]))
		if cc & (_GT|_EQ) != 0:
			pc=o[0]

	elif op == 15: # CMP
		WriteDebug("CMP {}, {}".format(o[0],o[1]))
		cc=0
		if o[0] == o[1]:
			cc|=_EQ
		if o[0] < o[1]:
			cc|=_LT
		if o[0] > o[1]:
			cc|=_GT

	elif op == 16: # PUSH
		WriteDebug("PUSH {}".format(o[0]))
		r[255]-=4  # Pre-decrement SP
		setI(r[255],o[0])

	elif op == 17: # POP
		WriteDebug("POP R{}".format(o[0]))
		r[o[0]]=getI(r[255])
		r[255]+=4  # Post-increment SP

	elif op == 18: # ADD
		WriteDebug("ADD R{}, {}".format(o[0],o[1]))
		r[o[0]]+=o[1]

	elif op == 19: # SUB
		WriteDebug("SUB R{}, {}".format(o[0],o[1]))
		r[o[0]]-=o[1]

	elif op == 20: # MUL
		WriteDebug("MUL R{}, {}".format(o[0],o[1]))
		r[o[0]]*=o[1]

	elif op == 21: # DIV
		WriteDebug("DIV R{}, {}".format(o[0],o[1]))
		r[o[0]]//=o[1]

	elif op == 22: # MOD
		WriteDebug("MOD R{}, {}".format(o[0],o[1]))
		r[o[0]]%=o[1]

	elif op == 23: # AND
		WriteDebug("AND R{}, {}".format(o[0],o[1]))
		r[o[0]]&=o[1]

	elif op == 24: # OR
		WriteDebug("OR R{}, {}".format(o[0],o[1]))
		r[o[0]]|=o[1]

	elif op == 25: # XOR
		WriteDebug("XOR R{}, {}".format(o[0],o[1]))
		r[o[0]]^=o[1]

	elif op == 26: # SHL
		WriteDebug("SHL R{}, {}".format(o[0],o[1]))
		r[o[0]]<<=o[1]

	elif op == 27: # SHR
		WriteDebug("SHR R{}, {}".format(o[0],o[1]))
		r[o[0]]>>=o[1]

	elif op == 28: # EXIT
		WriteDebug("EXIT {}".format(o[0]))
		exit_code=o[0]
		running=False

	elif op == 29: # PRINTLN
		s=getS(o[0],o[1])
		WriteDebug("PRINTLN {}, {} ({})".format(o[0],o[1],s))
		print(s)
		sys.stdout.flush()

	elif op == 30: # PRINT
		s=getS(o[0],o[1])
		WriteDebug("PRINT {}, {} ({})".format(o[0],o[1],s))
		print(s,end="")
		sys.stdout.flush()

	elif op == 31: # RUN
		s=getS(o[0],o[1])
		WriteDebug("RUN {}, {} ({})".format(o[0],o[1],s))
		os.system(s)

	else:
		WriteDebug("Unsupported op0={} @ pc={}".format(op0,pc))
		running=False

sys.exit(exit_code)
