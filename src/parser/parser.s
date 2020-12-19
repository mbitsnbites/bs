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
; Internal register allocation (used by most parsing routines):
;   r128 = current character
;   r129 = current character position (memory pointer)
;
;   r130-r133: Value 1
;     r130 = Value 1 type
;     r131 = Value 1 value
;     r132 = Value 1 size
;     r133 = Value 1 objref
;
;   r140-r143: Value 2
;     r140 = Value 2 type
;     r141 = Value 2 value
;     r142 = Value 2 size
;     r143 = Value 2 objref
;
;   r150 = current line number
;   r151 = start of current line
; -------------------------------------------------------------------------------------------------

; -------------------------------------------------------------------------------------------------
; parse_program() - Run a BS program.
;
; Input:
;   r1 = Start of BS string
;
; Output:
;   r1 = Exit status (0 for success)
; -------------------------------------------------------------------------------------------------

parse_program:
    ; Store the stack pointer for doing a "longjmp" style exit.
    stw     sp, z, #_parse_longjmp_sp

    mov     r129, r1        ; r129 = Start of program string
    ldb     r128, r129, z   ; r128 = Current (first) character

    mov     r150, #1        ; Line number = 1
    mov     r151, r129      ; Start of first line

parse_next_line:
    ; Find the start of a statement (skip spaces).
1$:
    jsr     parse_spaces
    cmp     r128, #10       ; LF
    beq     2$
    cmp     r128, #0        ; End of script
    beq     4$
    jsr     parse_statement
    jmp     parse_next_line

    ; Next line.
2$:
    add     r150, #1        ; Increment line counter
    mov     r151, r129
    add     r151, #1        ; Start of the next line (accurate for both LF and CRLF line endings)

    ; Next character.
3$:
    add     r129, #1
    ldb     r128, r129, z
    jmp     1$

    ; Parse done.
4$:
    mov     r1, #0
    rts

_parse_longjmp_sp:
    .word   0


; -------------------------------------------------------------------------------------------------
; Errors.
; -------------------------------------------------------------------------------------------------

parse_err_invalid_name:
    mov     r50, #parse_err_invalid_name_str
    mov     r51, #parse_err_invalid_name_str_size
    jmp     parse_error

parse_err_invalid_name_str:
    .ascii  "Invalid name"
    parse_err_invalid_name_str_size = *-parse_err_invalid_name_str

parse_err_not_implemented:
    mov     r50, #parse_err_not_implemented_str
    mov     r51, #parse_err_not_implemented_str_size
    jmp     parse_error

parse_err_not_implemented_str:
    .ascii  "Not implemented"
    parse_err_not_implemented_str_size = *-parse_err_not_implemented_str

parse_err_premature_end:
    mov     r50, #parse_err_premature_end_str
    mov     r51, #parse_err_premature_end_str_size
    jmp     parse_error

parse_err_premature_end_str:
    .ascii  "Premature end of file"
    parse_err_premature_end_str_size = *-parse_err_premature_end_str

parse_err_invalid:
    mov     r50, #parse_err_invalid_str
    mov     r51, #parse_err_invalid_str_size
    jmp     parse_error

parse_err_invalid_str:
    .ascii  "Invalid operation"
    parse_err_invalid_str_size = *-parse_err_invalid_str

parse_err_syntax_error:
    mov     r50, #parse_err_syntax_error_str
    mov     r51, #parse_err_syntax_error_str_size
    jmp     parse_error

parse_err_syntax_error_str:
    .ascii  "Syntax error"
    parse_err_syntax_error_str_size = *-parse_err_syntax_error_str

parser_err_out_of_memory:
    mov     r50, #parser_err_out_of_memory_str
    mov     r51, #parser_err_out_of_memory_str_size
    jmp     parse_error

parser_err_out_of_memory_str:
    .ascii  "Out of memory"
    parser_err_out_of_memory_str_size = *-parser_err_out_of_memory_str


; -------------------------------------------------------------------------------------------------
; Common error reporting routine.
;
; Input:
;   r50 = Error type string
;   r51 = Error type string length
;
; This routine exits the parser (does a "longjmp").
; -------------------------------------------------------------------------------------------------

parse_error:
    mov     r52, #parse_error_str1
    print   r52, #parse_error_str1_size

    mov     r1, r150
    jsr     int2str
    print   r1, r2

    mov     r52, #parse_error_str2
    print   r52, #parse_error_str2_size

    println r50, r51

    ; Print failing line (first, get length of line).
    mov     r52, r151
    mov     r53, #0
1$:
    ldb     r1, r52, r53
    cmp     r1, #10
    beq     2$
    cmp     r1, #0
    beq     2$
    add     r53, #1
    jmp     1$
2$:
    println r52, r53

    ; Print indication of failure.
    mov     r53, #parse_error_str3
    mov     r52, r151
3$:
    cmp     r52, r129
    beq     4$
    print   r53, #1
    add     r52, #1
    jmp     3$
4$:
    mov     r53, #parse_error_str4
    println r53, #1

    ldw     sp, z, #_parse_longjmp_sp
    mov     r1, #1
    rts

parse_error_str1:
    .ascii "*** Error in line "
    parse_error_str1_size = *-parse_error_str1

parse_error_str2:
    .ascii ": "
    parse_error_str2_size = *-parse_error_str2

parse_error_str3:
    .ascii " "

parse_error_str4:
    .ascii "^"


; -------------------------------------------------------------------------------------------------
; parse_spaces()
;
; Input:
;   r128 = current character
;   r129 = current parse position
;
; Output:
;   r128 = current character
;   r129 = current parse position
; -------------------------------------------------------------------------------------------------

parse_spaces:
1$:
    cmp     r128, #32       ; SPACE
    beq     2$
    cmp     r128, #9        ; TAB
    beq     2$
    cmp     r128, #13       ; CR
    beq     2$
    cmp     r128, #35       ; "#" - start of line comment
    beq     3$
    rts
2$:
    add     r129, #1
    ldb     r128, r129, z
    jmp     1$

    ; Find end of line comment (i.e. LF).
3$:
    add     r129, #1
    ldb     r128, r129, z
    cmp     r128, #10       ; LF
    bne     3$
    rts



; -------------------------------------------------------------------------------------------------
; parse_memcmp()
;
; Input:
;   r131 = start of str1
;   r132 = length of str1
;   r141 = start of str2
;   r142 = length of str2
;
; Output:
;   cc = status (EQ if equal, otherwise not equal)
;
; Clobbered:
;   r200, r201, r202
; -------------------------------------------------------------------------------------------------

parse_memcmp:
    cmp     r132, r142          ; Same length?
    bne     2$

    mov     r200, #0
1$:
    ldb     r201, r131, r200
    ldb     r202, r141, r200
    cmp     r201, r202
    bne     2$
    add     r200, #1
    cmp     r200, r132
    bne     1$
2$:
    rts


; -------------------------------------------------------------------------------------------------
; parse_statement()
;
; Input:
;   r128 = current character
;   r129 = current parse position
;
; Output:
;   r128 = current character
;   r129 = current parse position
; -------------------------------------------------------------------------------------------------

parse_statement:
    ; Extract a valid name (a statement always starts with a valid name).
    jsr     parse_name

    ; Check for reserved commands ("if", "while", "end", ...)
    cmp     r132, #2
    blt     4$
    bgt     1$

    ; Length = 2
    mov     r142, #2
    mov     r141, #_str_if
    jsr     parse_memcmp
    beq     parse_if

1$:
    cmp     r132, #3
    bgt     2$

    ; Length = 3
    mov     r142, #3
    mov     r141, #_str_end
    jsr     parse_memcmp
    beq     parse_end
    mov     r141, #_str_for
    jsr     parse_memcmp
    beq     parse_for

2$:
    cmp     r132, #4
    bgt     3$

    ; Length = 4
    mov     r142, #4
    mov     r141, #_str_else
    jsr     parse_memcmp
    beq     parse_else

3$:
    cmp     r132, #5
    bgt     4$

    ; Length = 5
    mov     r142, #5
    mov     r141, #_str_elsif
    jsr     parse_memcmp
    beq     parse_elsif
    mov     r141, #_str_while
    jsr     parse_memcmp
    beq     parse_while

    ; Is this an assignment (followed by "=") or a function call (followed by "("))?
4$:
    jsr     parse_spaces
    cmp     r128, #61       ; "="
    beq     parse_assignment
    cmp     r128, #40       ; "("
    beq     parse_function_call

    ; Something else, i.e. incorrect syntax.
    jmp     parse_err_syntax_error


; -------------------------------------------------------------------------------------------------
; parse_name()
;
; Input:
;   r128 = current character
;   r129 = current parse position
;
; Output:
;   r128 = current character
;   r129 = current parse position
;   r130 = _VAL_TYPE_STR
;   r131 = start of name (value)
;   r132 = length of name
;   r133 = _NULL (no objref)
; -------------------------------------------------------------------------------------------------

parse_name:
    mov     r131, r129      ; r131 = start of name

    ; The first char must be in [a-zA-Z_]
    cmp     r128, #122      ; "z"
    bgt     4$
    cmp     r128, #97       ; "a"
    bge     1$
    cmp     r128, #95       ; "_"
    beq     1$
    cmp     r128, #65       ; "A"
    blt     4$
    cmp     r128, #90       ; "Z"
    bgt     4$
1$:
    add     r129, #1
    ldb     r128, r129, z

    ; Chars 2.. must be in [a-zA-Z0-9_]
2$:
    cmp     r128, #122      ; "z"
    bgt     4$
    cmp     r128, #97       ; "a"
    bge     3$
    cmp     r128, #95       ; "_"
    beq     3$
    cmp     r128, #48       ; "0"
    blt     4$
    cmp     r128, #57       ; "9"
    ble     3$
    cmp     r128, #65       ; "A"
    blt     4$
    cmp     r128, #90       ; "Z"
    bgt     4$
3$:
    add     r129, #1
    ldb     r128, r129, z
    jmp     2$

    ; End of name.
4$:
    mov     r132, r129
    sub     r132, r131      ; length of name string
    cmp     r132, #0
    beq     parse_err_invalid_name
    mov     r130, #_VAL_TYPE_STR
    mov     r133, #_NULL
    rts


; -------------------------------------------------------------------------------------------------
; parse_number()
;
; Input:
;   r128 = current character
;   r129 = current parse position
;
; Output:
;   r128 = current character
;   r129 = current parse position
;   r130 = _VAL_TYPE_INT
;   r131 = integer number (value)
;   r132 = 0 (no str)
;   r133 = _NULL (no objref)
; -------------------------------------------------------------------------------------------------

parse_number:
    mov     r131, #0

1$:
    ; Numeric characters are [0-9].
    cmp     r128, #48       ; "0"
    blt     2$
    cmp     r128, #57       ; "9"
    bgt     2$

    ; Convert from decimal ASCII to integer.
    sub     r128, #48
    mul     r131, #10
    add     r131, r128

    add     r129, #1
    ldb     r128, r129, z
    jmp     1$

2$:
    mov     r130, #_VAL_TYPE_INT
    mov     r132, #0
    mov     r133, #_NULL
    rts


; -------------------------------------------------------------------------------------------------
; parse_expression()
;
; Input:
;   r128 = current character
;   r129 = current parse position
;
; Output:
;   r128 = current character
;   r129 = current parse position
;   r130 = type
;   r131 = value
;   r132 = strlen
;   r133 = objref
; -------------------------------------------------------------------------------------------------

parse_expression:
    ; TODO(m): Implement me!
    jmp     parse_err_not_implemented


; -------------------------------------------------------------------------------------------------
; parse_if()
; -------------------------------------------------------------------------------------------------

parse_if:
    ; TODO(m): Implement me!
    jmp     parse_err_not_implemented


; -------------------------------------------------------------------------------------------------
; parse_end()
; -------------------------------------------------------------------------------------------------

parse_end:
    ; TODO(m): Implement me!
    jmp     parse_err_not_implemented


; -------------------------------------------------------------------------------------------------
; parse_for()
; -------------------------------------------------------------------------------------------------

parse_for:
    ; TODO(m): Implement me!
    jmp     parse_err_not_implemented


; -------------------------------------------------------------------------------------------------
; parse_else()
; -------------------------------------------------------------------------------------------------

parse_else:
    ; TODO(m): Implement me!
    jmp     parse_err_not_implemented


; -------------------------------------------------------------------------------------------------
; parse_elsif()
; -------------------------------------------------------------------------------------------------

parse_elsif:
    ; TODO(m): Implement me!
    jmp     parse_err_not_implemented


; -------------------------------------------------------------------------------------------------
; parse_while()
; -------------------------------------------------------------------------------------------------

parse_while:
    ; TODO(m): Implement me!
    jmp     parse_err_not_implemented


; -------------------------------------------------------------------------------------------------
; parse_assignment()
; -------------------------------------------------------------------------------------------------

parse_assignment:
    ; TODO(m): Implement me!
    jmp     parse_err_not_implemented


; -------------------------------------------------------------------------------------------------
; parse_function_call()
; -------------------------------------------------------------------------------------------------

parse_function_call:
    ; TODO(m): Implement me!
    jmp     parse_err_not_implemented



; -------------------------------------------------------------------------------------------------
; Strings.
; -------------------------------------------------------------------------------------------------

_str_if:
    .ascii  "if"
_str_end:
    .ascii  "end"
_str_for:
    .ascii  "for"
_str_else:
    .ascii  "else"
_str_elsif:
    .ascii  "elsif"
_str_while:
    .ascii  "while"
