@echo off
REM -*- mode: batch; tab-width: 4; indent-tabs-mode: nil; -*-
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
set p=5C000000
set /A ps=20

REM Stuff for handling ASCII conversions.
REM TODO(m): Would love to support UTF-8 and more control characters!
setlocal DisableDelayedExpansion
REM NOTE: The two empty lines after the AX10 definition are required!
REM NOMINIFY
set AX10=^


REM MINIFY
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
for %%i in (0 0 1 1 2 2 0 0 0 0 0 0 0 0 0 1 0 0 0 0 0 0 0 0 0 0 0 0 0 1 1 1) do (
    set ninr[!n!]=%%i
    set /A n+=1
)
set /A n=0
for %%i in (0 1 1 1 1 1 1 1 0 1 1 1 1 1 1 1 1 0 1 1 1 1 1 1 1 1 1 1 1 1 1 1) do (
    set ninx[!n!]=%%i
    set /A n+=1
)

REM Note: We leave the memory empty and rely on well-behaving code (i.e. that
REM does not read undefined values).

REM Clear execution state.
set /A pc=1
set /A cc=0
for /L %%n in (0,1,255) do set /A reg[%%n]=0

REM Convert the hex string to bytes and store it in the memory.
for /L %%n in (0,1,9) do set /A X%%n=%%n
set /A XA=10
set /A XB=11
set /A XC=12
set /A XD=13
set /A XE=14
set /A XF=15
call :WriteDebug "prg_size=%ps%"
set /A a=1
set /A i=0
:l1
    set "c1=!p:~%i%,1!"
    set /A c1=X%c1%
    set /A i+=1
    set "c2=!p:~%i%,1!"
    set /A c2=X%c2%
    set /A i+=1
    set /A "b=(c1<<4)|c2"
    set /A m[!a!]=b
    set /A a+=1
    call :WriteDebug "(c1,c2)=(!c1!,!c2!) = (!b!)"
    if %a% lss %ps% goto :l1

REM Main execution loop.
set /A exit_code=1
set /A running=1
:mxl
    if %running% EQU 0 exit /B %exit_code%

    REM Read the next opcode.
    set /A pc0=pc
    set /A op0=!m[%pc%]!
    set /A pc+=1

    REM Decode the opcode:
    REM   Bits 0-5: operation
    REM   Bits 6-7: argument type
    set /A "at=op0>>6"
    set /A "op=op0&63"

    call :WriteDebug "PC=%pc0% CC=%cc% OP=%op0% OP*=%op% AT=%at%"
    if %op% LSS 1 goto :Ibad
    if %op% GTR 31 goto :Ibad

    REM Read the operands.
    set /A k=0
    set /A n=!nout[%op%]!
    :l3
        if %k% EQU %n% goto :o2
        REM Get register number (0-255)
        set /A o[!k!]=!m[%pc%]!
        set /A pc+=1
        set /A k+=1
        goto :l3
    :o2
    set /A n=k+!ninr[%op%]!
    :l4
        if %k% EQU %n% goto :o3
        REM Get register value
        set /A v=!m[%pc%]!
        set /A o[!k!]=!reg[%v%]!
        set /A pc+=1
        set /A k+=1
        goto :l4
    :o3
    set /A n=k+!ninx[%op%]!
    :l5
        if %k% EQU %n% goto :o4
        if %at% EQU 3 (
            REM 32-bit immediate.
            set /A b0=m[!pc!]
            set /A pc+=1
            set /A b1=m[!pc!]
            set /A pc+=1
            set /A b2=m[!pc!]
            set /A pc+=1
            set /A b3=m[!pc!]
            set /A pc+=1
            set /A "v=b0|(b1<<8)|(b2<<16)|(b3<<24)"
        ) else (
            REM Arg types 0-2 use a single byte.
            set /A v=m[!pc!]
            set /A pc+=1

            if %at% EQU 0 (
                REM Register value.
                set /A v=reg[!v!]
            ) else (
                REM Convert unsigned to signed byte (-128..127).
                if !v! GTR 127 set /A v-=256

                if %at% EQU 2 (
                    REM 8-bit PC-relative offset.
                    set /A v+=pc0
                )
                REM else v=v (at=1, 8-bit signed immedate)
            )
        )
        set /A o[!k!]=v
        set /A k+=1
        goto :l5
    :o4

    REM Execute the instruction.
    goto :I%op%
    :I1
        call :WriteDebug "MOV R!o[0]!, !o[1]!"
        set /A reg[!o[0]!]=o[1]
        goto :mxl

    :I2
        call :WriteDebug "LDB R!o[0]!, !o[1]!, !o[2]!"
        set /A a=o[1]+o[2]
        set /A reg[!o[0]!]=m[!a!]
        goto :mxl

    :I3
        call :WriteDebug "LDW R!o[0]!, !o[1]!, !o[2]!"
        set /A a=o[1]+o[2]
        set /A b0=m[!a!]
        set /A a+=1
        set /A b1=m[!a!]
        set /A a+=1
        set /A b2=m[!a!]
        set /A a+=1
        set /A b3=m[!a!]
        set /A "v=b0|(b1<<8)|(b2<<16)|(b3<<24)"
        set /A reg[!o[0]!]=v
        goto :mxl

    :I4
        call :WriteDebug "STB !o[0]!, !o[1]!, !o[2]!"
        set /A a=o[1]+o[2]
        set /A "m[!a!]=o[0]&255"
        goto :mxl

    :I5
        call :WriteDebug "STW !o[0]!, !o[1]!, !o[2]!"
        set /A a=o[1]+o[2]
        set /A v=o[0]
        set /A "m[!a!]=v&255"
        set /A a+=1
        set /A "m[!a!]=(v>>8)&255"
        set /A a+=1
        set /A "m[!a!]=(v>>16)&255"
        set /A a+=1
        set /A "m[!a!]=(v>>24)&255"
        goto :mxl

    :I6
        call :WriteDebug "JMP !o[0]!"
        set /A pc=o[0]
        goto :mxl

    :I7
        call :WriteDebug "JSR !o[0]!"
        set /A reg[255]-=4
        set /A a=reg[255]
        set /A "m[!a!]=pc&255"
        set /A a+=1
        set /A "m[!a!]=(pc>>8)&255"
        set /A a+=1
        set /A "m[!a!]=(pc>>16)&255"
        set /A a+=1
        set /A "m[!a!]=(pc>>24)&255"
        set /A pc=o[0]
        goto :mxl

    :I8
        call :WriteDebug "RTS"
        set /A a=reg[255]
        set /A b0=m[!a!]
        set /A a+=1
        set /A b1=m[!a!]
        set /A a+=1
        set /A b2=m[!a!]
        set /A a+=1
        set /A b3=m[!a!]
        set /A "pc=b0|(b1<<8)|(b2<<16)|(b3<<24)"
        set /A reg[255]+=4
        goto :mxl

    :I9
        call :WriteDebug "BEQ !o[0]!"
        set /A "v=cc&_EQ"
        if !v! NEQ 0 set /A pc=o[0]
        goto :mxl

    :I10
        call :WriteDebug "BNE !o[0]!"
        set /A "v=cc&_EQ"
        if !v! EQU 0 set /A pc=o[0]
        goto :mxl

    :I11
        call :WriteDebug "BLT !o[0]!"
        set /A "v=cc&_LT"
        if !v! NEQ 0 set /A pc=o[0]
        goto :mxl

    :I12
        call :WriteDebug "BLE !o[0]!"
        set /A "v=(cc&_LT)|(cc&_EQ)"
        if !v! NEQ 0 set /A pc=o[0]
        goto :mxl

    :I13
        call :WriteDebug "BGT !o[0]!"
        set /A "v=cc&_GT"
        if !v! NEQ 0 set /A pc=o[0]
        goto :mxl

    :I14
        call :WriteDebug "BGE !o[0]!"
        set /A "v=(cc&_GT)|(cc&_EQ)"
        if !v! NEQ 0 set /A pc=o[0]
        goto :mxl

    :I15
        call :WriteDebug "CMP !o[0]!, !o[1]!"
        set /A cc=0
        if !o[0]! EQU !o[1]! set /A "cc|=_EQ"
        if !o[0]! LSS !o[1]! set /A "cc|=_LT"
        if !o[0]! GTR !o[1]! set /A "cc|=_GT"
        goto :mxl

    :I16
        call :WriteDebug "PUSH !o[0]!"
        set /A reg[255]-=4
        set /A a=reg[255]
        set /A v=o[0]
        set /A "m[!a!]=v&255"
        set /A a+=1
        set /A "m[!a!]=(v>>8)&255"
        set /A a+=1
        set /A "m[!a!]=(v>>16)&255"
        set /A a+=1
        set /A "m[!a!]=(v>>24)&255"
        goto :mxl

    :I17
        call :WriteDebug "POP R!o[0]!"
        set /A a=reg[255]
        set /A b0=m[!a!]
        set /A a+=1
        set /A b1=m[!a!]
        set /A a+=1
        set /A b2=m[!a!]
        set /A a+=1
        set /A b3=m[!a!]
        set /A "reg[!o[0]!]=b0|(b1<<8)|(b2<<16)|(b3<<24)"
        set /A reg[255]+=4
        goto :mxl

    :I18
        call :WriteDebug "ADD R!o[0]!, !o[1]!"
        set /A reg[!o[0]!]+=o[1]
        goto :mxl

    :I19
        call :WriteDebug "SUB R!o[0]!, !o[1]!"
        set /A reg[!o[0]!]-=o[1]
        goto :mxl

    :I20
        call :WriteDebug "MUL R!o[0]!, !o[1]!"
        set /A reg[!o[0]!]*=o[1]
        goto :mxl

    :I21
        call :WriteDebug "DIV R!o[0]!, !o[1]!"
        set /A reg[!o[0]!]/=o[1]
        goto :mxl

    :I22
        call :WriteDebug "MOD R!o[0]!, !o[1]!"
        set /A reg[!o[0]!]%%=o[1]
        goto :mxl

    :I23
        call :WriteDebug "AND R!o[0]!, !o[1]!"
        set /A "reg[!o[0]!]&=o[1]"
        goto :mxl

    :I24
        call :WriteDebug "OR R!o[0]!, !o[1]!"
        set /A "reg[!o[0]!]|=o[1]"
        goto :mxl

    :I25
        call :WriteDebug "XOR R!o[0]!, !o[1]!"
        set /A reg[!o[0]!]^=o[1]
        goto :mxl

    :I26
        call :WriteDebug "SHL R!o[0]!, !o[1]!"
        set /A "reg[!o[0]!]<<=o[1]"
        goto :mxl

    :I27
        call :WriteDebug "SHR R!o[0]!, !o[1]!"
        set /A "reg[!o[0]!]>>=o[1]"
        goto :mxl

    :I28
        call :WriteDebug "EXIT !o[0]!"
        set /A exit_code=o[0]
        set /A running=0
        goto :mxl

    :I29
        call :getS "!o[0]!" "!o[1]!"
        call :WriteDebug "PRINTLN !o[0]! !o[1]! (%s%)"
        echo %s%
        goto :mxl

    :I30
        call :getS "!o[0]!" "!o[1]!"
        call :WriteDebug "PRINT !o[0]! !o[1]! (%s%)"
        REM TODO(m): Implement print without a newline.
        echo %s%
        goto :mxl

    :I31
        call :getS "!o[0]!" "!o[1]!"
        call :WriteDebug "RUN !o[0]! !o[1]! (%s%)"
        %s%
        goto :mxl

    :Ibad
        call :WriteDebug "Unsupported op0=%op0% @ pc=%pc%"
        set /A running=0
        goto :mxl


REM Helper functions.

:WriteDebug
  echo DEBUG: %~1 1>&2
  exit /B 0

:getS
  REM Extract the string from memory.
  set a=%~1%
  set l=%~2%
  set /A a2=a+l
  set s=
  :gsl
    set /A c=!m[%a%]!
    set d=!asc:~%c%,1!
    for %%i in (10 33 34 37 38 60 62 124) do if %c%==%%i set "d=^!AX%c%^!"
    set "s=!s!!d!"
    set /A a=a+1
    if %a% leq %a2% goto :gsl
  exit /B 0
