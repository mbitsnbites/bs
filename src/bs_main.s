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
    .include    parser/parser.s

main:
    jsr     mem_init

    ; Test the parser.
    mov     r1, #bs_source
    jsr     parse_program

    ; Allocate three blocks.
    mov     r1, 1000
    jsr     malloc
    mov     r128, r1
    mov     r1, 200
    jsr     malloc
    mov     r129, r1
    mov     r1, 92929
    jsr     malloc
    mov     r130, r1

    ; Free a block and allocate again.
    mov     r1, r129
    jsr     free
    mov     r1, #123
    jsr     malloc

    mov     r50, #command
    run     r50, #command_size

    jsr     print_test
    jsr     loop_test

    mov     r50, #done_text
    println r50, #done_text_size

    mov     r1, #0
    rts

print_test:
    mov     r1, #mem_start
    mov     r2, #hello_text
    mov     r3, #hello_text_size
    jsr     memcpy
    mov     r50, #mem_start
    println r50, #hello_text_size
    rts

loop_test:
    mov     r50, #loop_start_text
    print   r50, #loop_start_text_size
    mov     r128, #20
1$:
    mov     r129, #1000
2$:
    sub     r129, #1
    cmp     r129, #0
    bne     2$
    mov     r50, #loop_text
    print   r50, #loop_text_size
    sub     r128, #1
    cmp     r128, #0
    bne     1$
    mov     r50, #loop_done_text
    println r50, #loop_done_text_size
    rts


hello_text:
    .ascii "Hello world!! 👍"
    hello_text_size = *-hello_text

done_text:
    .ascii "Program finished."
    done_text_size = *-done_text

loop_start_text:
    .ascii "Looping (1000 loops per .): "
    loop_start_text_size = *-loop_start_text
loop_text:
    .ascii "."
    loop_text_size = *-loop_text
loop_done_text:
    .ascii " Done!"
    loop_done_text_size = *-loop_done_text

command:
    .ascii "cmake --version"
    command_size = *-command

; Test BS program.
bs_source:
    .asciz  "foo = 123\nif foo > 7\n  apa = \"Hello world!\"\n  println(apa)\nend"

; -------------------------------------------------------------------------------------------------
; The end of the program is the start of the working memory.
; -------------------------------------------------------------------------------------------------

mem_start:

