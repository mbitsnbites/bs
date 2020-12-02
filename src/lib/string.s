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
    mov     r6, r3
    shr     r6, #2      ; r6 = number of 32-bit words
    cmp     r6, #0
    beq     2$

    mov     r7, r6
    shl     r7, #2
    sub     r3, r7      ; r3 = number of trailing bytes

    mov     r5, r2
    add     r5, r7      ; r5 = word end of src
1$:
    ldw     r4, r2
    stw     r4, r1
    add     r2, #4
    add     r1, #4
    cmp     r2, r5
    bne     1$

2$:
    cmp     r3, #0
    beq     4$          ; Nothing to do?

    add     r3, r2      ; r3 = end of src
3$:
    ldb     r4, r2
    stb     r4, r1
    add     r2, #1
    add     r1, #1
    cmp     r2, r3
    bne     3$
4$:
    rts


; -------------------------------------------------------------------------------------------------
; void strcpy(string* dst, const string* src)
; Copy a string.
; -------------------------------------------------------------------------------------------------

strcpy:
    ldw     r3, r2
    add     r3, #4              ; num_bytes = strlen + 4
    jmp     memcpy

