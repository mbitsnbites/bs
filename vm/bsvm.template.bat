@echo off
REM -*- mode: batch; tab-width: 2; indent-tabs-mode: nil; -*-
REM -----------------------------------------------------------------------------------------------
REM Copyright (c) 2020 Marcus Geelnard
REM
REM This software is provided 'as-is', without any express or implied warranty. In no event will
REM the authors be held liable for any damages arising from the use of this software.
REM
REM Permission is granted to anyone to use this software for any purpose, including commercial
REM applications, and to alter it and redistribute it freely, subject to the following
REM restrictions:
REM
REM  1. The origin of this software must not be misrepresented; you must not claim that you wrote
REM     the original software. If you use this software in a product, an acknowledgment in the
REM     product documentation would be appreciated but is not required.
REM
REM  2. Altered source versions must be plainly marked as such, and must not be misrepresented as
REM     being the original software.
REM
REM  3. This notice may not be removed or altered from any source distribution.
REM -----------------------------------------------------------------------------------------------

setlocal EnableDelayedExpansion

REM Define the BS VM program. We use a hex string.
REM DON'T MODIFY THE FOLLOWING TWO LINES! THEY ARE REPLACED BY THE BUILD PROCESS!
set prg=0A7F220135999ABCDEF20931437608132870123BBABABBB28971287912347891679
set /A prg_size=20

REM Stuff for handling ASCII conversions.
REM TODO(m): Would love to support UTF-8 and more control characters!
REM NOTE: The two empty lines after the AX10 definition are required!
setlocal DisableDelayedExpansion
set AX10=^


set AX33=!
set AX34="
set AX37=%%
set AX38=^&
set AX60=^<
set AX62=^>
set AX124=^|
setlocal EnableDelayedExpansion
set "asc=          _                      __#$__'()*+,-./0123456789:;_=_?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\]^_`abcdefghijklmnopqrstuvwxyz{_}~"

REM Constants.
set /A _EQ=1
set /A _LT=2
set /A _GT=4

REM Instruction operand configuration (one element per instruction).
REM
REM  * nout - Number of output (or in/out) register operands.
REM  * ninr - Number of input register operands.
REM  * ninx - Number of "final" input operands (any operand kind).
REM
REM  OP:                        1 1 1 1 1 1 1 1 1 1 2 2 2 2 2 2 2 2 2 2 3 3
REM         0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
set /A n=0
for %%i in (0 1 1 1 0 0 0 0 0 0 0 0 0 0 0 0 0 1 1 1 1 1 1 1 1 1 1 1 0 0 0 0) do (
  set nout[!n!]=%%i
  set /A n+=1
)
set /A n=0
for %%i in (0 0 1 1 2 2 0 0 0 0 0 0 0 0 0 1 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0) do (
  set ninr[!n!]=%%i
  set /A n+=1
)
set /A n=0
for %%i in (0 1 1 1 1 1 1 1 0 1 1 1 1 1 1 1 1 0 1 1 1 1 1 1 1 1 1 1 1 1 1 1) do (
  set ninx[!n!]=%%i
  set /A n+=1
)

REM Note: We leave the RAM empty and rely on well-behaving code (i.e. that
REM does not read undefined values).

REM Clear execution state.
set /A pc=0
set /A instrPC=0
set /A cc=0
for /L %%n in (0,1,255) do set /A reg[%%n]=0

REM Convert the hex string to bytes and store it in the RAM.
for /L %%n in (0,1,9) do set /A X%%n=%%n
set /A XA=10
set /A XB=11
set /A XC=12
set /A XD=13
set /A XE=14
set /A XF=15
call :WriteDebug "prg_size=%prg_size%"
set /A a=0
set /A i=0
:l1
  set "c1=!prg:~%i%,1!"
  set /A c1=X%c1%
  set /A i+=1
  set "c2=!prg:~%i%,1!"
  set /A c2=X%c2%
  set /A i+=1
  set /A "b=(c1<<4)|c2"
  set /A ram[!a!]=b
  set /A a+=1
  call :WriteDebug "(c1,c2)=(!c1!,!c2!) = (!b!)"
  if %a% lss %prg_size% goto :l1

REM Main execution loop.
set /A exit_code=1
set /A running=1
:mainloop
  if %running% EQU 0 exit /B %exit_code%

  REM Read the next opcode.
  set /A instrPC=pc
  set /A op=!ram[%pc%]!
  set /A pc+=1

  REM Decode the opcode:
  REM   Bits 0-5: operation
  REM   Bits 6-7: argument type
  set /A "arg_type=op>>6"
  set /A "operation=op&63"

  call :WriteDebug "PC=%instrPC% CC=%cc% OP=%op% OP*=%operation% AT=%arg_type%"
  if %operation% LSS 1 goto :Ibad
  if %operation% GTR 31 goto :Ibad

  REM Read the operands.
  set /A k=0
  set /A n=!nout[%operation%]!
  :l3
    if %k% EQU %n% goto :o2
    REM Get register number (0-255)
    set /A ops[!k!]=!ram[%pc%]!
    set /A pc+=1
    set /A k+=1
    goto :l3
  :o2
  set /A n=k+!ninr[%operation%]!
  :l4
    if %k% EQU %n% goto :o3
    REM Get register value
    set /A v=!ram[%pc%]!
    set /A ops[!k!]=!reg[%v%]!
    set /A pc+=1
    set /A k+=1
    goto :l4
  :o3
  set /A n=k+!ninx[%operation%]!
  :l5
    if %k% EQU %n% goto :o4
    if %arg_type% EQU 3 (
      REM 32-bit immediate.
      set /A b0=ram[!pc!]
      set /A pc+=1
      set /A b1=ram[!pc!]
      set /A pc+=1
      set /A b2=ram[!pc!]
      set /A pc+=1
      set /A b3=ram[!pc!]
      set /A pc+=1
      set /A "v=b0|(b1<<8)|(b2<<16)|(b3<<24)"
    ) else (
      REM Arg types 0-2 use a single byte.
      set /A v=ram[!pc!]
      set /A pc+=1

      if %arg_type% EQU 0 (
        REM Register value.
        set /A v=reg[!v!]
      ) else (
        REM Convert unsigned to signed byte (-128..127).
        if !v! GTR 127 set /A v-=256

        if %arg_type% EQU 2 (
          REM 8-bit PC-relative offset.
          set /A v+=instrPC
        )
        REM else v=v (arg_type=1, 8-bit signed immedate)
      )
    )
    set /A ops[!k!]=v
    set /A k+=1
    goto :l5
  :o4

  REM Execute the instruction.
  goto :I%operation%
  :I1
    call :WriteDebug "MOV R!ops[0]!, !ops[1]!"
    set /A reg[!ops[0]!]=ops[1]
    goto :mainloop

  :I2
    call :WriteDebug "LDB R!ops[0]!, !ops[1]!, !ops[2]!"
    set /A a=ops[1]+ops[2]
    set /A reg[!ops[0]!]=ram[!a!]
    goto :mainloop

  :I3
    call :WriteDebug "LDW R!ops[0]!, !ops[1]!, !ops[2]!"
    set /A a=ops[1]+ops[2]
    set /A b0=ram[!a!]
    set /A a+=1
    set /A b1=ram[!a!]
    set /A a+=1
    set /A b2=ram[!a!]
    set /A a+=1
    set /A b3=ram[!a!]
    set /A "v=b0|(b1<<8)|(b2<<16)|(b3<<24)"
    set /A reg[!ops[0]!]=v
    goto :mainloop

  :I4
    call :WriteDebug "STB !ops[0]!, !ops[1]!, !ops[2]!"
    set /A a=ops[1]+ops[2]
    set /A "ram[!a!]=ops[0]&255"
    goto :mainloop

  :I5
    call :WriteDebug "STW !ops[0]!, !ops[1]!, !ops[2]!"
    set /A a=ops[1]+ops[2]
    set /A v=ops[0]
    set /A "ram[!a!]=v&255"
    set /A a+=1
    set /A "ram[!a!]=(v>>8)&255"
    set /A a+=1
    set /A "ram[!a!]=(v>>16)&255"
    set /A a+=1
    set /A "ram[!a!]=(v>>24)&255"
    goto :mainloop

  :I6
    call :WriteDebug "JMP !ops[0]!"
    set /A pc=ops[0]
    goto :mainloop

  :I7
    call :WriteDebug "JSR !ops[0]!"
    set /A reg[255]-=4
    set /A a=reg[255]
    set /A "ram[!a!]=pc&255"
    set /A a+=1
    set /A "ram[!a!]=(pc>>8)&255"
    set /A a+=1
    set /A "ram[!a!]=(pc>>16)&255"
    set /A a+=1
    set /A "ram[!a!]=(pc>>24)&255"
    set /A pc=ops[0]
    goto :mainloop

  :I8
    call :WriteDebug "RTS"
    set /A a=reg[255]
    set /A b0=ram[!a!]
    set /A a+=1
    set /A b1=ram[!a!]
    set /A a+=1
    set /A b2=ram[!a!]
    set /A a+=1
    set /A b3=ram[!a!]
    set /A "pc=b0|(b1<<8)|(b2<<16)|(b3<<24)"
    set /A reg[255]+=4
    goto :mainloop

  :I9
    call :WriteDebug "BEQ !ops[0]!"
    set /A "v=cc&_EQ"
    if !v! NEQ 0 set /A pc=ops[0]
    goto :mainloop

  :I10
    call :WriteDebug "BNE !ops[0]!"
    set /A "v=cc&_EQ"
    if !v! EQU 0 set /A pc=ops[0]
    goto :mainloop

  :I11
    call :WriteDebug "BLT !ops[0]!"
    set /A "v=cc&_LT"
    if !v! NEQ 0 set /A pc=ops[0]
    goto :mainloop

  :I12
    call :WriteDebug "BLE !ops[0]!"
    set /A "v=(cc&_LT)|(cc&_EQ)"
    if !v! NEQ 0 set /A pc=ops[0]
    goto :mainloop

  :I13
    call :WriteDebug "BGT !ops[0]!"
    set /A "v=cc&_GT"
    if !v! NEQ 0 set /A pc=ops[0]
    goto :mainloop

  :I14
    call :WriteDebug "BGE !ops[0]!"
    set /A "v=(cc&_GT)|(cc&_EQ)"
    if !v! NEQ 0 set /A pc=ops[0]
    goto :mainloop

  :I15
    call :WriteDebug "CMP !ops[0]!, !ops[1]!"
    set /A cc=0
    if !ops[0]! EQU !ops[1]! set /A "cc|=_EQ"
    if !ops[0]! LSS !ops[1]! set /A "cc|=_LT"
    if !ops[0]! GTR !ops[1]! set /A "cc|=_GT"
    goto :mainloop

  :I16
    call :WriteDebug "PUSH !ops[0]!"
    set /A reg[255]-=4
    set /A a=reg[255]
    set /A v=ops[0]
    set /A "ram[!a!]=v&255"
    set /A a+=1
    set /A "ram[!a!]=(v>>8)&255"
    set /A a+=1
    set /A "ram[!a!]=(v>>16)&255"
    set /A a+=1
    set /A "ram[!a!]=(v>>24)&255"
    goto :mainloop

  :I17
    call :WriteDebug "POP R!ops[0]!"
    set /A a=reg[255]
    set /A b0=ram[!a!]
    set /A a+=1
    set /A b1=ram[!a!]
    set /A a+=1
    set /A b2=ram[!a!]
    set /A a+=1
    set /A b3=ram[!a!]
    set /A "reg[!ops[0]!]=b0|(b1<<8)|(b2<<16)|(b3<<24)"
    set /A reg[255]+=4
    goto :mainloop

  :I18
    call :WriteDebug "ADD R!ops[0]!, !ops[1]!"
    set /A reg[!ops[0]!]+=ops[1]
    goto :mainloop

  :I19
    call :WriteDebug "SUB R!ops[0]!, !ops[1]!"
    set /A reg[!ops[0]!]-=ops[1]
    goto :mainloop

  :I20
    call :WriteDebug "MUL R!ops[0]!, !ops[1]!"
    set /A reg[!ops[0]!]*=ops[1]
    goto :mainloop

  :I21
    call :WriteDebug "DIV R!ops[0]!, !ops[1]!"
    set /A reg[!ops[0]!]/=ops[1]
    goto :mainloop

  :I22
    call :WriteDebug "MOD R!ops[0]!, !ops[1]!"
    set /A reg[!ops[0]!]%%=ops[1]
    goto :mainloop

  :I23
    call :WriteDebug "AND R!ops[0]!, !ops[1]!"
    set /A "reg[!ops[0]!]&=ops[1]"
    goto :mainloop

  :I24
    call :WriteDebug "OR R!ops[0]!, !ops[1]!"
    set /A "reg[!ops[0]!]|=ops[1]"
    goto :mainloop

  :I25
    call :WriteDebug "XOR R!ops[0]!, !ops[1]!"
    set /A reg[!ops[0]!]^=ops[1]
    goto :mainloop

  :I26
    call :WriteDebug "SHL R!ops[0]!, !ops[1]!"
    set /A "reg[!ops[0]!]<<=ops[1]"
    goto :mainloop

  :I27
    call :WriteDebug "SHR R!ops[0]!, !ops[1]!"
    set /A "reg[!ops[0]!]>>=ops[1]"
    goto :mainloop

  :I28
    call :WriteDebug "EXIT !ops[0]!"
    set /A exit_code=ops[0]
    set /A running=0
    goto :mainloop

  :I29
    call :getString "!ops[0]!"
    call :WriteDebug "PRINTLN !ops[0]! (%str%)"
    echo %str%
    goto :mainloop

  :I30
    call :getString "!ops[0]!"
    call :WriteDebug "PRINT !ops[0]! (%str%)"
    REM TODO(m): Implement print without a newline.
    echo %str%
    goto :mainloop

  :I31
    call :getString "!ops[0]!"
    call :WriteDebug "RUN !ops[0]! (%str%)"
    %str%
    goto :mainloop

  :Ibad
    call :WriteDebug "Unsupported op=%op% @ pc=%pc%"
    set /A running=0
    goto :mainloop


REM Helper functions.

:WriteDebug
  echo DEBUG: %~1 1>&2
  exit /B 0

:getString
  REM Read the string length (32-bit integer).
  set a=%~1%
  set /A b0=!ram[%a%]!
  set /A a=a+1
  set /A b1=!ram[%a%]!
  set /A a=a+1
  set /A b2=!ram[%a%]!
  set /A a=a+1
  set /A b3=!ram[%a%]!
  set /A "l=b0|(b1<<8)|(b2<<16)|(b3<<24)"

  REM Extract the string from memory.
  set /A a2=a+l
  set /A a=a+1
  set str=
  :getStringLoop
    set /A c=!ram[%a%]!
    set d=!asc:~%c%,1!
    for %%i in (10 33 34 37 38 60 62 124) do if %c%==%%i set "d=^!AX%c%^!"
    set "str=!str!!d!"
    set /A a=a+1
    if %a% leq %a2% goto :getStringLoop
  exit /B 0
