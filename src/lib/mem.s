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
; The memory allocater uses a packed array of memory blocks. Each block looks like this:
;
;   +--------+------+-------+-------------------------------------------------+
;   | Offset | Size | Type  | Description                                     |
;   +--------+------+-------+-------------------------------------------------+
;   | 0      | 4    | int32 | size (number of bytes)                          |
;   | 4      | 1    | uint8 | kind (0 = free, 1 = allocated, 2 = end of list) |
;   | 5      | size | -     | (user data)                                     |
;   +--------+------+-------+-------------------------------------------------+
;
; -------------------------------------------------------------------------------------------------

; The memory size must be matched by the VM implementation.
_MEM_END = 1048576
_STACK_SIZE = 4096


; -------------------------------------------------------------------------------------------------
; mem_init()
; Initialize the memory allocator.
; -------------------------------------------------------------------------------------------------

mem_init:
    mov     r1, #mem_start      ; r1 = Start of allocatable memory
    mov     r2, #_MEM_END
    sub     r2, r1              ; r2 = Memory size

    ; Create the first free block.
    mov     r3, r2              ; size = the whole memory...
    sub     r3, #10             ; ...minus the size of two blocks
    stw     r3, r1, #0          ; size
    mov     r4, #0
    stb     r4, r1, #4          ; kind = 0 (free)

    ; Create the last block.
    add     r1, #5
    add     r1, r3
    mov     r4, #0
    stw     r4, r1, #0          ; size = 0
    mov     r4, #2
    stb     r4, r1, #4          ; kind = 2 (end)

    rts


; -------------------------------------------------------------------------------------------------
; void* malloc(int32_t size)
; Allocate a chunk of memory.
; -------------------------------------------------------------------------------------------------

malloc:
    mov     r2, #mem_start      ; r2 = Memory start

    mov     r10, r1
    add     r10, #5             ; minimum block size required for splitting a block into two

    ; First fit: Find the first free block that is large enough.
1$:
    ldw     r3, r2, #0          ; r3 = candidate_size
    ldb     r4, r2, #4          ; r4 = kind
    cmp     r4, #2
    beq     5$                  ; kind == 2 (end)?
    cmp     r4, #0
    bne     2$                  ; kind != 0 (free)?
    cmp     r1, r3
    beq     4$                  ; size == candidate_size?
    cmp     r10, r3
    blt     3$                  ; size+5 < candidate_size?

    ; On to the next block.
2$:
    add     r2, #5
    add     r2, r3              ; Skip ahead +candidate_size
    jmp     1$

    ; We found a block that's larger than the requested size.
    ; We need to split the block into two.
3$:
    mov     r5, r2
    add     r5, #5
    add     r5, r1              ; r5 = start of the new free block
    stw     r1, r2, #0          ; new size

    sub     r3, r1
    sub     r3, #5              ; Free size of next block
    stw     r3, r5, #0
    stb     r4, r5, #4          ; kind of next block = same as the old block

    ; We found a block that's exactly the requested size.
4$:
    mov     r1, #1
    stb     r1, r2, #4          ; new kind = 1 (allocated)
    mov     r1, r2
    add     r1, #5              ; Return the block start address
    rts

    ; No more free memory.
5$:
    mov     r1, #0
    rts


; -------------------------------------------------------------------------------------------------
; void free(void* ptr)
; Free a chunk of memory.
; -------------------------------------------------------------------------------------------------

free:
    cmp     r1, #0
    beq     2$
    ldw     r4, r1, #-5 ; r4 = block size
    ldb     r5, r1, #-4 ; r5 = kind
    cmp     r5, #1
    bne     2$          ; kind != 1 (allocated) ?

    ; Check if next block is also free - if so, merge the two blocks.
    mov     r6, r1
    add     r6, #5
    add     r6, r4
    ldb     r8, r6, #4  ; r8 = next block kind
    cmp     r8, #1
    bne     1$

    ; Next block is free, so merge the two blocks.
    ldw     r7, r6, #0  ; r7 = next block size
    add     r4, r7
    add     r4, #5
    stw     r4, r1, #-5 ; size = merged size

    ; Next block is not free, so just mark the current block as free.
1$:
    stb     z, r1, #-1  ; kind = 0 (free)

2$:
    rts
