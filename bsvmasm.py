#!/usr/bin/env python3
# -*- mode: python; tab-width: 4; indent-tabs-mode: nil; -*-
# -------------------------------------------------------------------------------------------------
# Copyright (c) 2020 Marcus Geelnard
#
# This software is provided 'as-is', without any express or implied warranty. In no event will the
# authors be held liable for any damages arising from the use of this software.
#
# Permission is granted to anyone to use this software for any purpose, including commercial
# applications, and to alter it and redistribute it freely, subject to the following restrictions:
#
#  1. The origin of this software must not be misrepresented; you must not claim that you wrote
#     the original software. If you use this software in a product, an acknowledgment in the
#     product documentation would be appreciated but is not required.
#
#  2. Altered source versions must be plainly marked as such, and must not be misrepresented as
#     being the original software.
#
#  3. This notice may not be removed or altered from any source distribution.
# -------------------------------------------------------------------------------------------------

import argparse
import struct
import os
import sys

# Supported operand types.
_NONE = 0
_REG = 1
_IMM8 = 2  # -128..127
_PCREL8 = 4  # PC relative -128..127
_IMM32 = 3  # -2147483648..2147483647

# Supported opcodes.
# fmt: off
_OPCODES = {
    # Move & Load / Store
    "MOV": {"descrs": [
        [0x01, _REG, _REG],
        [0x41, _REG, _IMM8],
        [0x81, _REG, _PCREL8],
        [0xc1, _REG, _IMM32],
    ]},
    "LDB": {"descrs": [
        [0x02, _REG, _REG, _REG],
        [0x42, _REG, _REG, _IMM8],
        [0x82, _REG, _REG, _PCREL8],
        [0xc2, _REG, _REG, _IMM32],
    ]},
    "LDW": {"descrs": [
        [0x03, _REG, _REG, _REG],
        [0x43, _REG, _REG, _IMM8],
        [0x83, _REG, _REG, _PCREL8],
        [0xc3, _REG, _REG, _IMM32],
    ]},
    "STB": {"descrs": [
        [0x04, _REG, _REG, _REG],
        [0x44, _REG, _REG, _IMM8],
        [0x84, _REG, _REG, _PCREL8],
        [0xc4, _REG, _REG, _IMM32],
    ]},
    "STW": {"descrs": [
        [0x05, _REG, _REG, _REG],
        [0x45, _REG, _REG, _IMM8],
        [0x85, _REG, _REG, _PCREL8],
        [0xc5, _REG, _REG, _IMM32],
    ]},

    # Unconditional Jump / Jump to Subroutine
    "JMP": {"descrs": [
        [0x06, _REG],
        [0x46, _IMM8],
        [0x86, _PCREL8],
        [0xc6, _IMM32],
    ]},
    "JSR": {"descrs": [
        [0x07, _REG],
        [0x47, _IMM8],
        [0x87, _PCREL8],
        [0xc7, _IMM32],
    ]},
    "RTS": {"descrs": [[0x08]]},

    # Conditional Branch
    "BEQ": {"descrs": [
        [0x09, _REG],
        [0x49, _IMM8],
        [0x89, _PCREL8],
        [0xc9, _IMM32],
    ]},
    "BNE": {"descrs": [
        [0x0a, _REG],
        [0x4a, _IMM8],
        [0x8a, _PCREL8],
        [0xca, _IMM32],
    ]},
    "BLT": {"descrs": [
        [0x0b, _REG],
        [0x4b, _IMM8],
        [0x8b, _PCREL8],
        [0xcb, _IMM32],
    ]},
    "BLE": {"descrs": [
        [0x0c, _REG],
        [0x4c, _IMM8],
        [0x8c, _PCREL8],
        [0xcc, _IMM32],
    ]},
    "BGT": {"descrs": [
        [0x0d, _REG],
        [0x4d, _IMM8],
        [0x8d, _PCREL8],
        [0xcd, _IMM32],
    ]},
    "BGE": {"descrs": [
        [0x0e, _REG],
        [0x4e, _IMM8],
        [0x8e, _PCREL8],
        [0xce, _IMM32],
    ]},

    # Comparison
    "CMP": {"descrs": [
        [0x0f, _REG, _REG],
        [0x4f, _REG, _IMM8],
        [0x8f, _REG, _PCREL8],
        [0xcf, _REG, _IMM32],
    ]},

    # Stack
    "PUSH": {"descrs": [[0x10, _REG]]},
    "POP":  {"descrs": [[0x11, _REG]]},

    # Arithmetic
    "ADD": {"descrs": [
        [0x12, _REG, _REG],
        [0x52, _REG, _IMM8],
        [0x92, _REG, _PCREL8],
        [0xd2, _REG, _IMM32],
    ]},
    "SUB": {"descrs": [
        [0x13, _REG, _REG],
        [0x53, _REG, _IMM8],
        [0x93, _REG, _PCREL8],
        [0xd3, _REG, _IMM32],
    ]},
    "MUL": {"descrs": [
        [0x14, _REG, _REG],
        [0x54, _REG, _IMM8],
        [0xd4, _REG, _IMM32],
    ]},
    "DIV": {"descrs": [
        [0x15, _REG, _REG],
        [0x55, _REG, _IMM8],
        [0xd5, _REG, _IMM32],
    ]},
    "MOD": {"descrs": [
        [0x16, _REG, _REG],
        [0x56, _REG, _IMM8],
        [0xd6, _REG, _IMM32],
    ]},

    # Logic
    "AND": {"descrs": [
        [0x17, _REG, _REG],
        [0x57, _REG, _IMM8],
        [0xd7, _REG, _IMM32],
    ]},
    "OR": {"descrs": [
        [0x18, _REG, _REG],
        [0x58, _REG, _IMM8],
        [0xd8, _REG, _IMM32],
    ]},
    "XOR": {"descrs": [
        [0x19, _REG, _REG],
        [0x59, _REG, _IMM8],
        [0xd9, _REG, _IMM32],
    ]},
    "SHL": {"descrs": [
        [0x1a, _REG, _REG],
        [0x5a, _REG, _IMM8],
    ]},
    "SHR": {"descrs": [
        [0x1b, _REG, _REG],
        [0x5b, _REG, _IMM8],
    ]},

    # High level system calls
    "EXIT": {"descrs": [
        [0x1c, _REG],
        [0x5c, _IMM8],
        [0xdc, _IMM32],
    ]},
    "PRINTLN": {"descrs": [
        [0x1d, _REG, _REG],
        [0x5d, _REG, _IMM8],
        [0x9d, _REG, _PCREL8],
        [0xdd, _REG, _IMM32],
    ]},
    "PRINT": {"descrs": [
        [0x1e, _REG, _REG],
        [0x5e, _REG, _IMM8],
        [0x9e, _REG, _PCREL8],
        [0xde, _REG, _IMM32],
    ]},
    "RUN": {"descrs": [
        [0x1f, _REG, _REG],
        [0x5f, _REG, _IMM8],
        [0x9f, _REG, _PCREL8],
        [0xdf, _REG, _IMM32],
    ]},
}
# fmt: on


class AsmError(Exception):
    def __init__(self, line_no, msg):
        self.line_no = line_no
        self.msg = msg


def parse_integer(s):
    # This supports decimal ('123'), hexadecimal ('0x123') and binary ('0b101').
    value = int(s, 0)
    return value


def extract_parts(line):
    parts = line.split()
    result = [parts[0]]
    for part in parts[1:]:
        result += [a for a in part.split(",") if a]
    return result


def translate_reg(operand, line_no):
    reg = operand.upper()
    if reg == "Z":
        reg = "R254"
    elif reg == "SP":
        reg = "R255"
    if len(reg) < 2 or reg[0] != "R" or reg[1] == "0":
        raise AsmError(line_no, "Bad register: {}".format(operand))
    try:
        reg_no = int(reg[1:])
    except KeyError:
        raise AsmError(line_no, "Bad register: {}".format(operand))
    return [reg_no]


def is_local_label(label):
    # We support gas style '123$' dollar local labels.
    if label.endswith("$"):
        try:
            int(label[:-1])
            return True
        except ValueError:
            return False
    return False


def mangle_local_label(label, scope_label):
    return "{}@{}".format(scope_label, label[:-1])


def translate_addr_or_number(
    string, labels, scope_label, line_no, first_pass, current_addr
):
    # Numeric literal?
    try:
        return parse_integer(string)
    except ValueError:
        pass

    # Current position?
    if string == "*":
        return current_addr

    # Label?
    # TODO(m): Add support for numerical offsets and relative +/- deltas.
    try:
        if is_local_label(string):
            if not scope_label:
                raise AsmError(line_no, "No scope for local label: {}".format(string))
            string = mangle_local_label(string, scope_label)
        return labels[string]
    except KeyError:
        if first_pass:
            return 2147483647  # Something large (worst case)
        raise AsmError(line_no, "Bad label: {}".format(string))


def translate_numeric_expression(
    string, labels, scope_label, line_no, first_pass, current_addr
):
    # This is a very dodgy arithmetic expression parser... The most important use-cases that we
    # want to support are "*-label" and "a+b+c".
    result = 0
    addends = [x.strip() for x in string.split("+")]
    for addend in addends:
        subtrahends = [x.strip() for x in addend.split("-")]
        mode = "add"
        for x in subtrahends:
            if x:
                value = translate_addr_or_number(
                    x, labels, scope_label, line_no, first_pass, current_addr
                )
            else:
                value = 0
            if mode == "add":
                result += value
            else:
                result -= value
            mode = "sub"

    return result


def translate_imm(
    operand, operand_type, labels, scope_label, line_no, first_pass, current_addr
):
    # Drop the optional "#" prefix.
    if operand[0] == "#":
        operand = operand[1:]

    value = translate_numeric_expression(
        operand, labels, scope_label, line_no, first_pass, current_addr
    )

    value_bits = {_IMM8: 8, _IMM32: 32}[operand_type]
    value_min = {_IMM8: -(1 << 7), _IMM32: -(1 << 31)}[operand_type]
    value_max = {_IMM8: (1 << 7) - 1, _IMM32: (1 << 31) - 1}[operand_type]
    num_bytes = {_IMM8: 1, _IMM32: 4}[operand_type]

    # Convert value to signed or unsigned.
    if value >= 2147483648:
        value = -((~(value - 1)) & 0xFFFFFFFF)

    if value < value_min or value > value_max:
        raise AsmError(
            line_no,
            "Immediate value out of range ({}..{}): {}".format(
                value_min, value_max, operand
            ),
        )
    value = value & ((1 << value_bits) - 1)

    # Convert to an array of bytes.
    byte_array = []
    for i in range(num_bytes):
        byte_array.append(value & 255)
        value = value >> 8
    return byte_array


def translate_pcrel(
    operand, operand_type, pc, labels, scope_label, line_no, first_pass, current_addr
):
    if first_pass:
        return [0]

    # Drop the optional "#" prefix.
    if operand[0] == "#":
        operand = operand[1:]

    target_address = translate_numeric_expression(
        operand, labels, scope_label, line_no, False, current_addr
    )
    offset = target_address - pc
    if offset < -128 or offset >= 128:
        raise AsmError(line_no, "Too large offset: {}".format(offset))
    return [offset & 255]


def translate_operation(
    operation,
    mnemonic,
    descr,
    pc,
    line_no,
    labels,
    scope_label,
    first_pass,
    current_addr,
):
    if len(operation) != len(descr):
        raise AsmError(
            line_no, "Expected {} arguments for {}".format(len(descr) - 1, mnemonic)
        )
    instr = [descr[0]]
    for k in range(1, len(descr)):
        operand = operation[k]
        operand_type = descr[k]
        if operand_type == _REG:
            instr.extend(translate_reg(operand, line_no))
        elif operand_type in [_IMM8, _IMM32]:
            instr.extend(
                translate_imm(
                    operand,
                    operand_type,
                    labels,
                    scope_label,
                    line_no,
                    first_pass,
                    current_addr,
                )
            )
        elif operand_type == _PCREL8:
            instr.extend(
                translate_pcrel(
                    operand,
                    operand_type,
                    pc,
                    labels,
                    scope_label,
                    line_no,
                    first_pass,
                    current_addr,
                )
            )

    return instr


def read_file(file_name):
    with open(file_name, "r") as f:
        lines = f.readlines()
    return lines


def preprocess(lines, file_dir):
    result = []
    for line in lines:
        lin = line.strip()
        if lin.startswith(".include"):
            include_file_name = os.path.join(file_dir, lin[8:].strip().replace('"', ""))
            include_lines = read_file(include_file_name)
            include_dir = os.path.dirname(include_file_name)
            result.extend(preprocess(include_lines, include_dir))
        else:
            result.append(lin)

    return result


def is_label_assignment(line):
    # Quick and dirty check.
    parts = line.split("=")
    if len(parts) != 2:
        return False
    if '"' in line:
        return False
    return True


def parse_assigned_label(line, labels, scope_label, line_no, first_pass, current_addr):
    parts_unfiltered = line.split("=")
    parts = []
    for part in parts_unfiltered:
        part = part.strip()
        if len(part) > 0:
            parts.append(part)
    if len(parts) != 2:
        raise AsmError(line_no, "Invalid label assignment: {}".format(line))
    label = parts[0]
    try:
        label_value = translate_numeric_expression(
            parts[1], labels, scope_label, line_no, first_pass, current_addr
        )
    except ValueError:
        raise AsmError(line_no, "Invalid integer value: {}".format(parts[1]))

    return label, label_value


def emit_utf8(c):
    if c < 0x00080:
        return struct.pack("B", c)
    elif c < 0x00800:
        return struct.pack("BB", 0b11000000 | (c >> 6), 0x80 | (c & 0x3F))
    elif c < 0x10000:
        return struct.pack(
            "BBB", 0b11100000 | (c >> 12), 0x80 | ((c >> 6) & 0x3F), 0x80 | (c & 0x3F)
        )
    else:
        return struct.pack(
            "BBBB",
            0b11110000 | (c >> 18),
            0x80 | ((c >> 12) & 0x3F),
            0x80 | ((c >> 6) & 0x3F),
            0x80 | (c & 0x3F),
        )


def compile_source(lines, verbosity_level, file_name):
    success = False
    labels = {}
    code_from_last_pass = b""
    try:
        for compilation_pass in range(1, 100):
            first_pass = compilation_pass == 1
            if verbosity_level >= 1:
                print(f"Pass {compilation_pass}")

            # Set the default start address.
            addr = 1  # The reset PC address = 0x00000001

            # Clear code and labels for this pass.
            code = b""
            new_labels = {}

            # Clear the scope for local labels.
            scope_label = ""

            inside_block_comment = False

            for line_no, raw_line in enumerate(lines, 1):
                line = raw_line

                # End of previously started block comment?
                if inside_block_comment:
                    comment_pos = line.find("*/")
                    if comment_pos < 0:
                        continue
                    inside_block_comment = False
                    line = line[(comment_pos + 2) :]

                # Remove line comment.
                # TODO(m): Handle multiple comments per line, etc, such as:
                # " ldi s1, /* Hello ; world */ #1234 /* More to come..."
                comment_pos = line.find(";")
                comment_pos2 = line.find("/*")
                if comment_pos2 >= 0 and (
                    comment_pos2 < comment_pos or comment_pos < 0
                ):
                    comment_pos = comment_pos2
                    inside_block_comment = True
                if comment_pos >= 0:
                    line = line[:comment_pos]

                # Strip head and tail whitespaces.
                line = line.strip()

                if len(line) == 0:
                    # This is an empty line.
                    pass

                elif line.endswith(":") or is_label_assignment(line):
                    # This is a label.
                    if line.endswith(":"):
                        label = line[:-1]
                        label_value = addr
                    else:
                        label, label_value = parse_assigned_label(
                            line, labels, scope_label, line_no, first_pass, addr
                        )
                    if " " in label or "@" in label:
                        raise AsmError(line_no, 'Bad label "{}"'.format(label))
                    if is_local_label(label):
                        # This is a local label - make it global.
                        if not scope_label:
                            raise AsmError(
                                line_no, "No scope for local label: {}".format(label)
                            )
                        label = mangle_local_label(label, scope_label)
                    else:
                        # This is a global label - use it as the scope label.
                        scope_label = label
                    if label in new_labels:
                        raise AsmError(
                            line_no, "Re-definition of label: {}".format(label)
                        )
                    new_labels[label] = label_value

                elif line.startswith("."):
                    # This is a data directive.
                    directive = extract_parts(line)

                    if directive[0] == ".align":
                        try:
                            value = parse_integer(directive[1])
                        except ValueError:
                            raise AsmError(
                                line_no, "Invalid alignment: {}".format(directive[1])
                            )
                        if value not in [1, 2, 4, 8, 16]:
                            raise AsmError(
                                line_no,
                                "Invalid alignment: {} (must be 1, 2, 4, 8 or 16)".format(
                                    value
                                ),
                            )
                        addr_adjust = addr % value
                        if addr_adjust > 0:
                            num_pad_bytes = value - addr_adjust
                            for k in range(num_pad_bytes):
                                code += struct.pack("B", 0)
                            addr += num_pad_bytes
                            if verbosity_level >= 2:
                                print(
                                    "Aligned pc to: {} (padded by {} bytes)".format(
                                        addr, num_pad_bytes
                                    )
                                )

                    elif directive[0] in [".byte", ".word", ".long", ".int"]:
                        pseudo_op = directive[0]
                        if pseudo_op in [".byte"]:
                            num_bits = 8
                            val_type = "B"
                        elif pseudo_op in [".word", ".long", ".int"]:
                            num_bits = 32
                            val_type = "<L"

                        val_size = num_bits >> 3
                        if not addr & (val_size - 1) == 0:
                            raise AsmError(
                                line_no,
                                "Data not aligned to a {} byte boundary".format(
                                    val_size
                                ),
                            )
                        for k in range(1, len(directive)):
                            try:
                                value = translate_numeric_expression(
                                    directive[k],
                                    labels,
                                    scope_label,
                                    line_no,
                                    first_pass,
                                    addr,
                                )
                            except ValueError:
                                raise AsmError(
                                    line_no, "Invalid integer: {}".format(directive[k])
                                )
                            # Convert value to unsigned.
                            if value < 0:
                                value = (1 << num_bits) + value
                            addr += val_size
                            code += struct.pack(val_type, value)

                    elif directive[0] in [".space", ".zero"]:
                        if len(directive) != 2:
                            raise AsmError(
                                line_no, "Invalid usage of {}".format(directive[0])
                            )
                        try:
                            size = parse_integer(directive[1])
                        except ValueError:
                            raise AsmError(
                                line_no, "Invalid size: {}".format(directive[1])
                            )
                        addr += size
                        for k in range(0, size):
                            code += struct.pack("b", 0)

                    elif directive[0] in [".ascii", ".asciz"]:
                        raw_text = line[len(directive[0]) :].strip()
                        first_quote = raw_text.find('"')
                        last_quote = raw_text.rfind('"')
                        if (
                            (first_quote < 0)
                            or (last_quote != (len(raw_text) - 1))
                            or (last_quote == first_quote)
                        ):
                            raise AsmError(
                                line_no, "Invalid string: {}".format(raw_text)
                            )
                        text = raw_text[(first_quote + 1) : last_quote]

                        str_code = b""
                        k = 0
                        while k < len(text):
                            char = text[k]
                            k += 1
                            if char == "\\":
                                if k == len(text):
                                    raise AsmError(
                                        line_no,
                                        "Premature end of string: {}".format(raw_text),
                                    )
                                control_char = text[k]
                                k += 1
                                if control_char.isdigit():
                                    char_code = parse_integer(control_char)
                                else:
                                    try:
                                        char_code = {
                                            "t": 9,
                                            "n": 10,
                                            "r": 13,
                                            "\\": 92,
                                            '"': 34,
                                        }[control_char]
                                    except KeyError:
                                        raise AsmError(
                                            line_no,
                                            "Bad control character: \\{}".format(
                                                control_char
                                            ),
                                        )
                            else:
                                char_code = ord(char)
                            char_utf8 = emit_utf8(char_code)
                            addr += len(char_utf8)
                            str_code += char_utf8

                        if directive[0] == ".asciz":
                            # .asciz => zero terminated string.
                            addr += 1
                            str_code += struct.pack("B", 0)

                        code += str_code

                    elif directive[0] in [".text", ".data", ".global", ".globl"]:
                        if verbosity_level >= 1:
                            print(
                                "{}:{}: WARNING: Ignoring directive: {}".format(
                                    file_name, line_no, directive[0]
                                )
                            )

                    else:
                        raise AsmError(
                            line_no, "Unknown directive: {}".format(directive[0])
                        )

                else:
                    # This is a machine code instruction.
                    operation = extract_parts(line)
                    full_mnemonic = operation[0].upper()
                    mnemonic = full_mnemonic
                    pc = addr  # Start PC for this instruction

                    try:
                        op_descr = _OPCODES[mnemonic]
                    except KeyError:
                        raise AsmError(
                            line_no, "Bad mnemonic: {}".format(full_mnemonic)
                        )

                    errors = []
                    translation_successful = False
                    descrs = op_descr["descrs"]
                    for descr in descrs:
                        try:
                            instr = translate_operation(
                                operation,
                                full_mnemonic,
                                descr,
                                pc,
                                line_no,
                                labels,
                                scope_label,
                                first_pass,
                                addr,
                            )
                            translation_successful = True
                            break
                        except AsmError as e:
                            errors.append(e.msg)
                    if not translation_successful:
                        msg = "Invalid operands for {}: {}".format(
                            full_mnemonic, ",".join(operation[1:])
                        )
                        for e in errors:
                            msg += "\n  Candidate: {}".format(e)
                        raise AsmError(line_no, msg)

                    if verbosity_level >= 2:
                        msg = format(addr, "08x") + ": "
                        for b in instr:
                            msg += format(b, "02x") + " "
                        msg += "   " * (6 - len(instr))
                        print(f"{msg} <= {operation}")

                    for b in instr:
                        code += struct.pack("<B", b)

                    addr += len(instr)

            # Do we have to do another pass?
            # We keep going until all labels have stabilized.
            if first_pass or new_labels != labels or code != code_from_last_pass:
                labels = new_labels
                code_from_last_pass = code
            else:
                success = True
                break

        if verbosity_level >= 1:
            print("--- Summary ---")

        # Dump label values.
        if verbosity_level >= 2:
            for label in labels:
                print("Label: {} = ".format(label) + format(labels[label], "08x"))

        # Pad the generated binary to an even 4-byte size.
        while len(code) & 3 != 0:
            code += struct.pack("<B", 0)
        if verbosity_level >= 1:
            print(f"Total size: {len(code)}")

    except AsmError as e:
        print(f"{file_name}:{e.line_no}: ERROR: {e.msg}")
        success = False

    return success, code


def compile_file(file_name, out_name, verbosity_level):
    if verbosity_level >= 1:
        print(f"Compiling {file_name}...")

    # Read the file, and preprocess it.
    file_dir = os.path.dirname(file_name)
    lines = read_file(file_name)
    lines = preprocess(lines, file_dir)

    # Compile to pre-processed source.
    (success, code) = compile_source(lines, verbosity_level, file_name)

    # Write the output file.
    if success:
        with open(out_name, "wb") as f:
            f.write(code)

    return success


def main():
    # Parse command line arguments.
    parser = argparse.ArgumentParser(
        description="A simple assembler for the BS Virtual Machine"
    )
    parser.add_argument(
        "files", metavar="FILE", nargs="+", help="the file(s) to process"
    )
    parser.add_argument("-o", "--output", help="output file")
    parser.add_argument("-v", "--verbose", action="store_true", help="be verbose")
    parser.add_argument(
        "-vv", "--extra-verbose", action="store_true", help="be extra verbose"
    )
    args = parser.parse_args()

    # Select verbosity level.
    verbosity_level = 0
    if args.verbose:
        verbosity_level = 1
    elif args.extra_verbose:
        verbosity_level = 2

    # Collect source -> output jobs.
    jobs = []
    if args.output is not None:
        if len(args.files) != 1:
            print(
                "Error: Only a single source file must be specified together with -o."
            )
            sys.exit(1)
        jobs.append({"src": args.files[0], "out": args.output})
    else:
        for file_name in args.files:
            out_name = os.path.splitext(file_name)[0] + ".bin"
            jobs.append({"src": file_name, "out": out_name})

    # Perform compilations.
    for job in jobs:
        if not compile_file(job["src"], job["out"], verbosity_level):
            sys.exit(1)


if __name__ == "__main__":
    main()
