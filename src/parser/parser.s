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
; parse_program() - Run a BS program.
;
; Input:
;   r1 = Start of BS string
;
; Output:
;   r1 = Exit status (0 for success)
;
; Internal register allocation (used by most parsing routines):
;   r128 = current character
;   r129 = current character position (memory pointer)
;   r130 = start of subpart (e.g. keyword)
;   r131 = length of subpart
;   r132 = 2nd string to compare with
;   r150 = current line number
;   r151 = start of current line
; -------------------------------------------------------------------------------------------------

parse_program:
    mov     r129, r1
    ldb     r128, r129, z

    mov     r150, #1        ; Line number = 1
    mov     r151, r129      ; Start of first line

parse_next_line:
    ; Find the start of a statement (skip spaces).
1$:
    cmp     r128, #32       ; SPACE
    beq     3$
    cmp     r128, #9        ; TAB
    beq     3$
    cmp     r128, #10       ; LF
    beq     2$
    cmp     r128, #13       ; CR
    beq     3$
    cmp     r128, #0        ; End of script
    bne     parse_statement

    ; Parse done.
    mov     r1, #0
    rts

2$:
    add     r150, #1        ; Increment line counter
    mov     r151, r129
    add     r151, #1        ; Start of the next line (accurate for both LF and CRLF line endings)
3$:
    add     r129, #1
    ldb     r128, r129, z
    jmp     1$


; -------------------------------------------------------------------------------------------------
; Errors.
; -------------------------------------------------------------------------------------------------

parse_err_invalid_name:
    mov     r1, #parse_err_invalid_name_str
    mov     r2, #parse_err_invalid_name_str_size
    jmp     parse_error

parse_err_invalid_name_str:
    .ascii  "Invalid name"
    parse_err_invalid_name_str_size = *-parse_err_invalid_name_str

parse_err_not_implemented:
    mov     r1, #parse_err_not_implemented_str
    mov     r2, #parse_err_not_implemented_str_size
    jmp     parse_error

parse_err_not_implemented_str:
    .ascii  "Not implemented"
    parse_err_not_implemented_str_size = *-parse_err_not_implemented_str

parse_err_premature_end:
    mov     r1, #parse_err_premature_end_str
    mov     r2, #parse_err_premature_end_str_size
    jmp     parse_error

parse_err_premature_end_str:
    .ascii  "Premature end of file"
    parse_err_premature_end_str_size = *-parse_err_premature_end_str

parse_err_syntax_error:
    mov     r1, #parse_err_syntax_error_str
    mov     r2, #parse_err_syntax_error_str_size
    jmp     parse_error

parse_err_syntax_error_str:
    .ascii  "Syntax error"
    parse_err_syntax_error_str_size = *-parse_err_syntax_error_str

parse_error:
    mov     r50, #parse_error_str
    print   r50, #parse_error_str_size
    println r1, r2
    mov     r1, #1
    rts

parse_error_str:
    .ascii "*** Error: "
    parse_error_str_size = *-parse_error_str


; -------------------------------------------------------------------------------------------------
; parse_consume_spaces()
;
; Input:
;   r128 = current character
;   r129 = current parse position
;
; Output:
;   r128 = current character
;   r129 = current parse position
; -------------------------------------------------------------------------------------------------

parse_consume_spaces:
1$:
    cmp     r128, #32       ; SPACE
    beq     2$
    cmp     r128, #9        ; TAB
    beq     2$
    cmp     r128, #13       ; CR
    beq     2$
    cmp     r128, #0        ; End of script
    beq     parse_err_premature_end
    rts
2$:
    add     r129, #1
    ldb     r128, r129, z
    jmp     1$


; -------------------------------------------------------------------------------------------------
; parse_memcmp()
;
; Input:
;   r130 = start of str1
;   r131 = number of characters (must be > 0)
;   r132 = start of str2
;
; Output:
;   cc = status (EQ if equal, otherwise comparison of first diffing byte)
;
; Clobbered:
;   r200, r201, r202
; -------------------------------------------------------------------------------------------------

parse_memcmp:
    mov     r200, #0
1$:
    ldb     r201, r130, r200
    ldb     r202, r132, r200
    cmp     r201, r202
    bne     2$
    add     r200, #1
    cmp     r200, r131
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
    cmp     r131, #2
    blt     4$
    bgt     1$

    ; Length = 2
    mov     r132, #_str_if
    jsr     parse_memcmp
    beq     parse_if

1$:
    cmp     r131, #3
    bgt     2$

    ; Length = 3
    mov     r132, #_str_end
    jsr     parse_memcmp
    beq     parse_end
    mov     r132, #_str_for
    jsr     parse_memcmp
    beq     parse_for

2$:
    cmp     r131, #4
    bgt     3$

    ; Length = 4
    mov     r132, #_str_else
    jsr     parse_memcmp
    beq     parse_else

3$:
    cmp     r131, #4
    bgt     4$

    ; Length = 5
    mov     r132, #_str_elsif
    jsr     parse_memcmp
    beq     parse_elsif
    mov     r132, #_str_while
    jsr     parse_memcmp
    beq     parse_while

    ; Is this an assignment (followed by "=") or a function call (followed by "("))?
4$:
    jsr     parse_consume_spaces
    cmp     r128, #61       ; "="
    beq     parse_assignment
    cmp     r128, #40       ; "("
    beq     parse_function_call

    jmp     parse_err_syntax_error

    ; TODO(m): Implement me!

    jmp     parse_next_line


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
;   r130 = start of name
;   r131 = length of name
; -------------------------------------------------------------------------------------------------

parse_name:
    mov     r130, r129      ; r130 = start of name

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
    mov     r131, r129
    sub     r131, r130      ; r131 = length of name string
    cmp     r131, #0
    beq     parse_err_invalid_name
    rts


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
