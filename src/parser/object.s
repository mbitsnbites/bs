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
; A BS object is defined by three fields:
;
;  +--------+------+-------+-----------------------------------------+
;  | Offset | Size | Name  | Description                             |
;  +--------+------+-------+-----------------------------------------+
;  | -8     | 4    | count | Reference count (>0 for objects in use) |
;  | -4     | 4    | size  | Size of object data (number of bytes)   |
;  |  0     | size | data  | Object data                             |
;  +--------+------+-------+-----------------------------------------+
;
; Note: The object reference handle is a pointer to the start of the object data (e.g. the start of
; the string for a string object). The object header fileds have a negative offset relative to the
; object reference handle.
; -------------------------------------------------------------------------------------------------

_OBJ_COUNT    = -8
_OBJ_SIZE     = -4
_OBJ_HDR_SIZE = 8


; -------------------------------------------------------------------------------------------------
; obj_new() - Create a new object.
;
; Input:
;   r1 = Object data size
;
; Output:
;   r1 = Object ptr
;
; Clobbered:
;   r2 - r49, r200
; -------------------------------------------------------------------------------------------------

obj_new:
    mov     r200, r1

    ; Allocate memory for the object.
    add     r1, #_OBJ_HDR_SIZE
    jsr     malloc
    cmp     r1, #0
    beq     parser_err_out_of_memory

    ; Field offsets are relative to the object data pointer.
    add     r1, #_OBJ_HDR_SIZE

    ; Fill out the object fields.
    mov     r2, #1
    stw     r2, r1, #_OBJ_COUNT
    stw     r200, r1, #_OBJ_SIZE

    rts


; -------------------------------------------------------------------------------------------------
; obj_incref() - Increase reference count.
;
; Input:
;   r1 = Object ptr (can be NULL)
;
; Clobbered:
;   r2
; -------------------------------------------------------------------------------------------------

obj_incref:
    cmp     r1, #_NULL    ; No object reference?
    beq     1$

    ; Increment the object reference.
    ldw     r2, r1, #_OBJ_COUNT
    add     r2, #1
    stw     r2, r1, #_OBJ_COUNT

1$:
    rts


; -------------------------------------------------------------------------------------------------
; obj_decref() - Decrease reference count.
;
; Input:
;   r1 = Object ptr (can be NULL)
;
; Clobbered:
;   r1 - r49
; -------------------------------------------------------------------------------------------------

obj_decref:
    cmp     r1, #_NULL    ; No object reference?
    beq     1$

    ; Decrement the reference count
    ldw     r2, r1, #_OBJ_COUNT
    sub     r2, #1
    stw     r2, r1, #_OBJ_COUNT

    ; Delete the object if we just dropped the last reference.
    cmp     r2, #0
    bgt     1$
    sub     r1, #_OBJ_HDR_SIZE
    jmp     free
    
1$:
    rts

