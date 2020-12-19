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

; -------------------------------------------------------------------------------------------------
; String functions.
; -------------------------------------------------------------------------------------------------

; -------------------------------------------------------------------------------------------------
; void memcpy(void* dst, const void* src, int32_t num_bytes)
; Copy a piece of memory.
; -------------------------------------------------------------------------------------------------

memcpy:
    mov     r8, #0

    mov     r6, r3
    shr     r6, #2      ; r6 = number of 32-bit words
    cmp     r6, #0
    beq     2$
    shl     r6, #2
1$:
    ldw     r4, r2, r8
    stw     r4, r1, r8
    add     r8, #4
    cmp     r8, r6
    bne     1$

2$:
    cmp     r3, #0
    beq     4$          ; Nothing to do?

3$:
    ldb     r4, r2, r8
    stb     r4, r1, r8
    add     r8, #1
    cmp     r8, r3
    bne     3$
4$:
    rts


; -------------------------------------------------------------------------------------------------
; int2str() - Convert an integer number to a string.
;
; Input:
;   r1 = integer number
;
; Output:
;   r1 = pointer to string start
;   r2 = size of string (number of bytes)
; -------------------------------------------------------------------------------------------------

int2str_max_str_len = 11    ; -2^31 => "-2147483648"

int2str:
    mov     r2, #4$
    mov     r3, #int2str_max_str_len

    ; Handle negative numbers.
    mov     r5, r1
    cmp     r5, #0
    bge     1$
    cmp     r5, #-2147483648 ; Special case (we can't negate -2147483648)
    beq     3$
    mov     r1, #0
    sub     r1, r5

1$:
    mov     r4, r1
    mod     r4, #10
    add     r4, #48         ; Convert decimal number to ASCII
    sub     r3, #1
    stb     r4, r2, r3
    div     r1, #10
    cmp     r1, #0
    bne     1$

    ; Inject a negative sign if necessary.
    cmp     r5, #0
    bge     2$
    sub     r3, #1
    mov     r4, #45         ; "-"
    stb     r4, r2, r3

2$:
    mov     r1, r2
    add     r1, r3          ; r1 = start of string
    mov     r2, #int2str_max_str_len
    sub     r2, r3          ; r2 = length of string
    rts

3$:
    mov     r1, #5$
    mov     r2, #int2str_max_str_len
    rts

4$:
    .space int2str_max_str_len

5$:
    .ascii "-2147483648"

