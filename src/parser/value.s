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
; A BS value is defined by four fields:
;   type:
;     0 = int
;     1 = bool
;     2 = str
;     3 = void
;   value:
;     type == void: unused
;     type == int:  Signed 32-bit value
;     type == bool: 0=false, 1=true
;     type == str:  Pointer to first character
;   length (only for str):
;     Number of bytes
;   object_reference (only for str):
;     0 = No object reference (constant data)
;     >0 = Pointer to object
; -------------------------------------------------------------------------------------------------

_VAL_TYPE_INT  = 0
_VAL_TYPE_BOOL = 1
_VAL_TYPE_STR  = 2
_VAL_TYPE_VOID = 3

_TRUE  = 1
_FALSE = 0

_NULL = 0


; -------------------------------------------------------------------------------------------------
; val_cmp_eq() - Compare two values for equality.
;
; Input:
;   r130 = Value 1 type
;   r131 = Value 1 value
;   r132 = Value 1 size
;   r133 = Value 1 objref
;
;   r140 = Value 2 type
;   r141 = Value 2 value
;   r142 = Value 2 size
;   r143 = Value 2 objref
;
; Output:
;   r130 = type (bool)
;   r131 = value (true/false)
;   r132 = size (0)
;   r133 = objref (null)
;
; Clobbered:
;   r1 - r49
; -------------------------------------------------------------------------------------------------

val_cmp_eq:
    ; We can not compare objects of different types.
    cmp     r130, r140
    bne     parse_err_invalid

    ; Two void values always compare equal.
    cmp     r130, #_VAL_TYPE_VOID
    beq     3$

    cmp     r130, #_VAL_TYPE_STR
    beq     1$

    ; int or bool: Compare the value field.
    cmp     r131, r141
    beq     3$
    jmp     4$

    ; str: Compare the string.
1$:
    ; Decrement input object reference counts (only necessary for strings).
    mov     r1, r133
    jsr     obj_decref
    mov     r1, r143
    jsr     obj_decref

    ; Strings with different lengths are not equal.
    cmp     r132, r142
    bne     4$

    ; Compare all characters.
    mov     r1, #0
2$:
    cmp     r1, r132
    beq     3$
    ldb     r2, r131, r1
    ldb     r3, r141, r1
    cmp     r2, r3
    bne     4$
    add     r1, #1
    jmp     2$

3$:
    mov     r131, #_TRUE
    jmp     5$
4$:
    mov     r131, #_FALSE
5$:

    ; Fill out the return value fields.
    mov     r130, #_VAL_TYPE_BOOL
    mov     r132, #0
    mov     r133, #_NULL
    rts


; -------------------------------------------------------------------------------------------------
; val_cmp_ne() - Compare two values for inequality.
;
; Input:
;   r130 = Value 1 type
;   r131 = Value 1 value
;   r132 = Value 1 size
;   r133 = Value 1 objref
;
;   r140 = Value 2 type
;   r141 = Value 2 value
;   r142 = Value 2 size
;   r143 = Value 2 objref
;
; Output:
;   r130 = type (bool)
;   r131 = value (true/false)
;   r132 = size (0)
;   r133 = objref (null)
;
; Clobbered:
;   r1 - r49
; -------------------------------------------------------------------------------------------------

val_cmp_ne:
    ; a != b <=> !(a == b)
    jsr     val_cmp_eq
    xor     r131, #1
    rts


; -------------------------------------------------------------------------------------------------
; val_cmp_lt() - Check if value 1 is less than value 2.
;
; Input:
;   r130 = Value 1 type
;   r131 = Value 1 value
;   r132 = Value 1 size
;   r133 = Value 1 objref
;
;   r140 = Value 2 type
;   r141 = Value 2 value
;   r142 = Value 2 size
;   r143 = Value 2 objref
;
; Output:
;   r130 = type (bool)
;   r131 = value (true/false)
;   r132 = size (0)
;   r133 = objref (null)
; -------------------------------------------------------------------------------------------------

val_cmp_lt:
    ; We can only compare two integer values.
    cmp     r130, r140
    bne     parse_err_invalid
    cmp     r130, #_VAL_TYPE_INT
    bne     parse_err_invalid

    ; Compare the value field.
    cmp     r131, r141
    mov     r131, #_TRUE
    blt     1$
    mov     r131, #_FALSE
1$:
    mov     r130, #_VAL_TYPE_BOOL
    mov     r132, #0
    mov     r133, #_NULL
    rts


; -------------------------------------------------------------------------------------------------
; val_cmp_le() - Check if value 1 is less than or equal to value 2.
;
; Input:
;   r130 = Value 1 type
;   r131 = Value 1 value
;   r132 = Value 1 size
;   r133 = Value 1 objref
;
;   r140 = Value 2 type
;   r141 = Value 2 value
;   r142 = Value 2 size
;   r143 = Value 2 objref
;
; Output:
;   r130 = type (bool)
;   r131 = value (true/false)
;   r132 = size (0)
;   r133 = objref (null)
; -------------------------------------------------------------------------------------------------

val_cmp_le:
    ; We can only compare two integer values.
    cmp     r130, r140
    bne     parse_err_invalid
    cmp     r130, #_VAL_TYPE_INT
    bne     parse_err_invalid

    ; Compare the value field.
    cmp     r131, r141
    mov     r131, #_TRUE
    ble     1$
    mov     r131, #_FALSE
1$:
    mov     r130, #_VAL_TYPE_BOOL
    mov     r132, #0
    mov     r133, #_NULL
    rts


; -------------------------------------------------------------------------------------------------
; val_cmp_gt() - Check if value 1 is greater than value 2.
;
; Input:
;   r130 = Value 1 type
;   r131 = Value 1 value
;   r132 = Value 1 size
;   r133 = Value 1 objref
;
;   r140 = Value 2 type
;   r141 = Value 2 value
;   r142 = Value 2 size
;   r143 = Value 2 objref
;
; Output:
;   r130 = type (bool)
;   r131 = value (true/false)
;   r132 = size (0)
;   r133 = objref (null)
; -------------------------------------------------------------------------------------------------

val_cmp_gt:
    ; a > b <=> !(a <= b)
    jsr     val_cmp_le
    xor     r131, #1
    rts


; -------------------------------------------------------------------------------------------------
; val_cmp_ge() - Check if value 1 is greater than or equal to value 2.
;
; Input:
;   r130 = Value 1 type
;   r131 = Value 1 value
;   r132 = Value 1 size
;   r133 = Value 1 objref
;
;   r140 = Value 2 type
;   r141 = Value 2 value
;   r142 = Value 2 size
;   r143 = Value 2 objref
;
; Output:
;   r130 = type (bool)
;   r131 = value (true/false)
;   r132 = size (0)
;   r133 = objref (null)
; -------------------------------------------------------------------------------------------------

val_cmp_ge:
    ; a >= b <=> !(a < b)
    jsr     val_cmp_lt
    xor     r131, #1
    rts

