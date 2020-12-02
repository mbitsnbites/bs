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
; Memory allocator.
;
; The memory allocater uses a singly linked list of mem_record:s:
;
;   struct mem_record {
;       int32_t size;
;       uint8_t kind;   // 0 = free, 1 = allocated, 2 = end of list
;   };
; -------------------------------------------------------------------------------------------------

; The memory size must be matched by the VM implementation.
_MEM_END = 1048576
_STACK_SIZE = 4096


; -------------------------------------------------------------------------------------------------
; mem_init()
; Initialize the memory allocator.
; -------------------------------------------------------------------------------------------------

mem_init:
    mov     r1, #mem_start      ; r1 = Memory start
    mov     r2, #_MEM_END
    sub     r2, r1              ; r2 = Memory size

    ; Create the first free block.
    mov     r3, r2              ; size = the whole memory...
    sub     r3, #10             ; ...minus the size of two blocks
    stw     r3, r1              ; size
    add     r1, #4
    mov     r4, #0
    stb     r4, r1              ; kind = 0 (free)

    ; Create the last block.
    add     r1, r3
    mov     r4, #0
    stw     r4, r1              ; size = 0
    add     r1, #4
    mov     r4, #2
    stb     r4, r1              ; kind = 2 (end)

    rts


; -------------------------------------------------------------------------------------------------
; void* malloc(int32_t size)
; Allocate a chunk of memory.
; -------------------------------------------------------------------------------------------------

malloc:
    mov     r2, #mem_start      ; r2 = Memory start

    ; First fit: Find the first free block that is large enough.
1$:
    ldw     r3, r2              ; r3 = candidate_size
    add     r2, #4
    ldb     r4, r2              ; r4 = kind
    add     r2, #1
    cmp     r4, #2
    beq     5$                  ; kind == 2 (end)?
    cmp     r4, #0
    bne     2$                  ; kind != 0 (free)?
    cmp     r1, r3
    blt     3$                  ; size < candidate_size?
    beq     4$                  ; size == candidate_size?

    ; On to the next block.
2$:
    add     r2, r3              ; Skip ahead +candidate_size
    jmp     1$

    ; We found a block that's larger than the requested size.
3$:
    mov     r5, r2
    add     r5, r3              ; r5 = start of the next block

    ; TODO(m): Implement me!
    jmp     5$

    ; We found a block that's exactly the requested size.
4$:
    ; TODO(m): Implement me!
    jmp     5$

    ; No more free memory.
5$:
    mov     r1, #0
    rts

