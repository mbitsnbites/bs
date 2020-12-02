; -*- mode: bsvmasm; tab-width: 4; indent-tabs-mode: nil; -*-
; -------------------------------------------------------------------------------------------------
; Copyright (c) 2020 Marcus Geelnard
;
; This software is provided 'as-is', without any express or implied warranty. In no event will the
; authors be held liable for any damages arising from the use of this software.
;
; Permission is granted to anyone to use this software for any purpose, including commercial
; applications, and to alter it and redistribute it freely, subject to the following restrictions:
;
;  1. The origin of this software must not be misrepresented; you must not claim that you wrote
;     the original software. If you use this software in a product, an acknowledgment in the
;     product documentation would be appreciated but is not required.
;
;  2. Altered source versions must be plainly marked as such, and must not be misrepresented as
;     being the original software.
;
;  3. This notice may not be removed or altered from any source distribution.
; -------------------------------------------------------------------------------------------------

; This is just a test program for the BS VM.

    .include    lib/crt0.s
    .include    lib/mem.s
    .include    lib/string.s

main:
    run     #command

    jsr     print_test
    jsr     loop_test

    println #done_text

    mov     r1, #0
    rts

print_test:
    mov     r1, #mem_start
    mov     r2, #hello_text
    jsr     strcpy
    println #mem_start
    rts

loop_test:
    print   #loop_start_text
    mov     r128, #20
1$:
    mov     r129, #1000
2$:
    sub     r129, #1
    cmp     r129, #0
    bne     2$
    print   #loop_text
    sub     r128, #1
    cmp     r128, #0
    bne     1$
    println #loop_done_text
    rts


hello_text:
    .string "Hello world!! 👍"

done_text:
    .string "Program finished."

loop_start_text:
    .string "Looping (1000 loops per .): "
loop_text:
    .string "."
loop_done_text:
    .string " Done!"

command:
    .string "cmake --version"


; -------------------------------------------------------------------------------------------------
; The end of the program is the start of the working memory.
; -------------------------------------------------------------------------------------------------

mem_start:

