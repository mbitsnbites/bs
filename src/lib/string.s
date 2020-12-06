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
; void strcpy(string* dst, const string* src)
; Copy a string.
; -------------------------------------------------------------------------------------------------

strcpy:
    ldw     r3, r2, #0
    add     r3, #4              ; num_bytes = strlen + 4
    jmp     memcpy

