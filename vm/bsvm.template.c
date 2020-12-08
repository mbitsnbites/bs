// -*- mode: c; tab-width: 2; indent-tabs-mode: nil; -*-
// -------------------------------------------------------------------------------------------------
// Copyright (c) 2020 Marcus Geelnard
//
// This software is provided 'as-is', without any express or implied warranty. In no event will the
// authors be held liable for any damages arising from the use of this software.
//
// Permission is granted to anyone to use this software for any purpose, including commercial
// applications, and to alter it and redistribute it freely, subject to the following restrictions:
//
//  1. The origin of this software must not be misrepresented; you must not claim that you wrote
//     the original software. If you use this software in a product, an acknowledgment in the
//     product documentation would be appreciated but is not required.
//
//  2. Altered source versions must be plainly marked as such, and must not be misrepresented as
//     being the original software.
//
//  3. This notice may not be removed or altered from any source distribution.
// -------------------------------------------------------------------------------------------------

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// Constants.
#define _EQ 1
#define _LT 2
#define _GT 4

// Define the BS VM program. We use a packed string (3 characters per 2 bytes).
const char p[]="DON'T MODIFY THIS LINE! IT IS REPLACED BY THE BUILD PROCESS!";

// Instruction operand configuration (one element per instruction).
//
//  * nout - Number of output (or in/out) register operands.
//  * ninr - Number of input register operands.
//  * ninx - Number of "final" input operands (any operand kind).
//
// OP:                                1 1 1 1 1 1 1 1 1 1 2 2 2 2 2 2 2 2 2 2 3 3
//                0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
const int nout[]={0,1,1,1,0,0,0,0,0,0,0,0,0,0,0,0,0,1,1,1,1,1,1,1,1,1,1,1,0,0,0,0},
          ninr[]={0,0,1,1,2,2,0,0,0,0,0,0,0,0,0,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0},
          ninx[]={0,1,1,1,1,1,1,1,0,1,1,1,1,1,1,1,1,0,1,1,1,1,1,1,1,1,1,1,1,1,1,1};

// Memory.
unsigned char* m;

// CPU state.
int r[256],pc,cc;

// Work variables.
char* s=0;

// Helper functions.
#define WriteDebug(...) fprintf(stderr,"DEBUG: "); fprintf(stderr,__VA_ARGS__); fprintf(stderr,"\n")

int getI(int a){
  return ((int)m[a])|(((int)m[a+1])<<8)|(((int)m[a+2])<<16)|(((int)m[a+3])<<24);
}

void getS(int a){
  // Read the string length (32-bit integer).
  int l=getI(a);

  // Extract the string from memory.
  free(s);
  s=malloc(l+1);
  memcpy(s,&m[a+4],l);
  s[l]=0;
}

int main(int argc, char** argv){
  int i,k,n,v,a;

  // Create memory.
  m=malloc(1<<20);

  // Clear execution state.
  pc=cc=0;
  for(i=0;i<255;++i)r[i]=0;

  // Convert the packed string to bytes and store it in the memory.
  v=(sizeof(p)*2)/3;
  WriteDebug("prg_size=%d",v);
  for(i=0;i<v/2;++i){
    int c1=p[i*3]-40,    // 6 bits (0-63)
        c2=p[i*3+1]-40,  // 5 bits (0-31)
        c3=p[i*3+2]-40;  // 5 bits (0-31)
    int b1=(c1<<2)|(c2>>3),
        b2=((c2&7)<<5)|c3;
    m[i*2]=b1;
    m[i*2+1]=b2;
    WriteDebug("(c1,c2,c3)=(%d,%d,%d) -> (%d,%d)",c1,c2,c3,b1,b2);
  }

  // Main execution loop.
  int exit_code=1,running=1;
  while(running){
    // Read the next opcode.
    int pc0=pc,
        op0=m[pc];
    ++pc;

    // Decode the opcode:
    //   Bits 0-5: operation
    //   Bits 6-7: argument type
    int at=op0>>6,
        op=op0&63;

    WriteDebug("PC=%d CC=%d OP=%d OP*=%d AT=%d",pc0,cc,op0,op,at);

    // Read the operands.
    int o[4];
    k=0;
    n=nout[op];
    for(;k<n;++k){
      // Get register number (0-255)
      o[k]=m[pc++];
    }
    n=k+ninr[op];
    for(;k<n;++k){
      // Get register value
      o[k]=r[m[pc++]];
    }
    n=k+ninx[op];
    for(;k<n;++k){
      if(at==3){
        // 32-bit immediate.
        v=getI(pc);
        pc+=4;
      } else {
        // Arg types 0-2 use a single byte.
        v=m[pc];
        ++pc;

        if(at==0){
          // Register value.
          v=r[v];
        } else {
          // Convert unsigned to signed byte (-128..127).
          if(v>127)v-=256;

          if(at==2){
            // 8-bit PC-relative offset.
            v+=pc0;
          }
          // else v=v (arg_type=1, 8-bit signed immedate)
        }
      }
      o[k]=v;
    }

    // Execute the instruction.
    switch (op){
    case 1: // MOV
      WriteDebug("MOV R%d, %d",o[0],o[1]);
      r[o[0]]=o[1];
      break;

    case 2: // LDB
      WriteDebug("LDB R%d, %d, %d",o[0],o[1],o[2]);
      r[o[0]]=m[o[1]+o[2]];
      break;

    case 3: // LDW
      WriteDebug("LDW R%d, %d, %d",o[0],o[1],o[2]);
      r[o[0]]=getI(o[1]+o[2]);
      break;

    case 4: // STB
      WriteDebug("STB %d, %d, %d",o[0],o[1],o[2]);
      m[o[1]+o[2]]=o[0]&255;
      break;

    case 5: // STW
      WriteDebug("STW %d, %d, %d",o[0],o[1],o[2]);
      a=o[1]+o[2];
      v=o[0];
      m[a]=v&255;
      m[a+1]=(v>>8)&255;
      m[a+2]=(v>>16)&255;
      m[a+3]=(v>>24)&255;
      break;

    case 6: // JMP
      WriteDebug("JMP %d",o[0]);
      pc=o[0];
      break;

    case 7: // JSR
      WriteDebug("JSR %d",o[0]);
      r[255]-=4;  // Pre-decrement SP
      a=r[255];
      m[a]=pc&255;
      m[a+1]=(pc>>8)&255;
      m[a+2]=(pc>>16)&255;
      m[a+3]=(pc>>24)&255;
      pc=o[0];
      break;

    case 8: // RTS
      WriteDebug("RTS");
      pc=getI(r[255]);
      r[255]+=4;  // Post-increment SP
      break;

    case 9: // BEQ
      WriteDebug("BEQ %d",o[0]);
      if(cc&_EQ)pc=o[0];
      break;

    case 10: // BNE
      WriteDebug("BNE %d",o[0]);
      if(!(cc&_EQ))pc=o[0];
      break;

    case 11: // BLT
      WriteDebug("BLT %d",o[0]);
      if(cc&_LT)pc=o[0];
      break;

    case 12: // BLE
      WriteDebug("BLE %d",o[0]);
      if(cc&(_LT|_EQ))pc=o[0];
      break;

    case 13: // BGT
      WriteDebug("BGT %d",o[0]);
      if(cc&_GT)pc=o[0];
      break;

    case 14: // BGE
      WriteDebug("BGE %d",o[0]);
      if(cc&(_GT|_EQ))pc=o[0];
      break;

    case 15: // CMP
      WriteDebug("CMP %d, %d",o[0],o[1]);
      cc=0;
      if(o[0]==o[1])cc|=_EQ;
      if(o[0]<o[1])cc|=_LT;
      if(o[0]>o[1])cc|=_GT;
      break;

    case 16: // PUSH
      WriteDebug("PUSH %d",o[0]);
      r[255]-=4;  // Pre-decrement SP
      a=r[255];
      v=o[0];
      m[a]=v&255;
      m[a+1]=(v>>8)&255;
      m[a+2]=(v>>16)&255;
      m[a+3]=(v>>24)&255;
      break;

    case 17: // POP
      WriteDebug("POP R%d",o[0]);
      r[o[0]]=getI(r[255]);
      r[255]+=4;  // Post-increment SP
      break;

    case 18: // ADD
      WriteDebug("ADD R%d, %d",o[0],o[1]);
      r[o[0]]+=o[1];
      break;

    case 19: // SUB
      WriteDebug("SUB R%d, %d",o[0],o[1]);
      r[o[0]]-=o[1];
      break;

    case 20: // MUL
      WriteDebug("MUL R%d, %d",o[0],o[1]);
      r[o[0]]*=o[1];
      break;

    case 21: // DIV
      WriteDebug("DIV R%d, %d",o[0],o[1]);
      r[o[0]]/=o[1];
      break;

    case 22: // MOD
      WriteDebug("MOD R%d, %d",o[0],o[1]);
      r[o[0]]%=o[1];
      break;

    case 23: // AND
      WriteDebug("AND R%d, %d",o[0],o[1]);
      r[o[0]]&=o[1];
      break;

    case 24: // OR
      WriteDebug("OR R%d, %d",o[0],o[1]);
      r[o[0]]|=o[1];
      break;

    case 25: // XOR
      WriteDebug("XOR R%d, %d",o[0],o[1]);
      r[o[0]]^=o[1];
      break;

    case 26: // SHL
      WriteDebug("SHL R%d, %d",o[0],o[1]);
      r[o[0]]<<=o[1];
      break;

    case 27: // SHR
      WriteDebug("SHR R%d, %d",o[0],o[1]);
      r[o[0]]>>=o[1];
      break;

    case 28: // EXIT
      WriteDebug("EXIT %d",o[0]);
      exit_code=o[0];
      running=0;
      break;

    case 29: // PRINTLN
      getS(o[0]);
      WriteDebug("PRINTLN %d (%s)",o[0],s);
      printf("%s\n",s);
      fflush(stdout);
      break;

    case 30: // PRINT
      getS(o[0]);
      WriteDebug("PRINT %d (%s)",o[0],s);
      printf("%s",s);
      fflush(stdout);
      break;

    case 31: // RUN
      getS(o[0]);
      WriteDebug("RUN %d (%s)",o[0],s);
      system(s);
      break;

    default:
      WriteDebug("Unsupported op=%d @ pc=%d",op,pc);
      running=0;
    }
  }

  exit(exit_code);
}
