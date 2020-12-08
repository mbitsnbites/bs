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
import bin2str
import bsvmasm
import os
import stat
import sys
from pathlib import Path

_REPO_ROOT = Path(__file__).parent
_OUT_DIR = _REPO_ROOT / "out"

_MAIN_SOURCE = _REPO_ROOT / "src/bs_main.s"

_BAT_FRONTEND_TEMPLATE = _REPO_ROOT / "vm/bs.template.bat"
_BAT_FRONTEND_OUT = _OUT_DIR / "bs.bat"
_SH_FRONTEND_TEMPLATE = _REPO_ROOT / "vm/bs.template"
_SH_FRONTEND_OUT = _OUT_DIR / "bs"

_BASHVM_TEMPLATE = _REPO_ROOT / "vm/bsvm.template.bash"
_BASHVM_OUT = _OUT_DIR / "bsvm.bash"
_BATVM_TEMPLATE = _REPO_ROOT / "vm/bsvm.template.bat"
_BATVM_OUT = _OUT_DIR / "bsvm.bat"
_CVM_TEMPLATE = _REPO_ROOT / "vm/bsvm.template.c"
_CVM_OUT = _OUT_DIR / "bsvm.c"
_PSVM_TEMPLATE = _REPO_ROOT / "vm/bsvm.template.ps1"
_PSVM_OUT = _OUT_DIR / "bsvm.ps1"
_PYVM_TEMPLATE = _REPO_ROOT / "vm/bsvm.template.py"
_PYVM_OUT = _OUT_DIR / "bsvm.py"


def read_file(name):
    lines = []
    with open(name, "rb") as f:
        for line in f.readlines():
            lines.append(line.decode("utf8").rstrip() + "\n")
    return lines


def write_file(name, lines, make_executable=False):
    with open(name, "wb") as f:
        for line in lines:
            f.write(line.encode("utf8"))

    if make_executable:
        st = os.stat(name)
        os.chmod(name, st.st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)


def compile_file(src_name, verbosity_level):
    srd_dir = src_name.parent
    lines = read_file(src_name)
    lines = bsvmasm.preprocess(lines, srd_dir)
    (success, code) = bsvmasm.compile_source(lines, verbosity_level, src_name)
    if not success:
        print(f"Unable to compile {src_name}")
        sys.exit(1)
    return code


def remove_line_comment(line, start_str="#"):
    slen = len(start_str)
    inside_string = False
    for k in range(len(line)):
        if line[k] in ['"', "'"] and (k == 0 or line[k-1] != "\\"):
            inside_string = not inside_string
        elif (not inside_string) and line[k:k+slen] == start_str:
            return line[:k].rstrip() + "\n"
    return line


def gen_bash(code, verbosity_level, debug):
    if verbosity_level >= 1:
        print(f"Generating {_BASHVM_OUT}")

    lines = read_file(_BASHVM_TEMPLATE)
    for k in range(len(lines)):
        line = lines[k]

        # Perform template substitutions.
        if line.startswith("p="):
            prg_str = bin2str.convert(code, use_hex=False)
            line = f"p='{prg_str}'\n"

        # Perform simple minification (except for debug builds).
        if not debug:
            # Remove indent.
            line = line.lstrip()

            # Remove comments (except the shebang).
            if k > 0:
                line = remove_line_comment(line)

            # Remove debug code and empty lines.
            if line.lstrip().startswith("WriteDebug") or line.strip() == "":
                line = ""

        lines[k] = line

    write_file(_BASHVM_OUT, lines, make_executable=True)


def gen_bat(code, verbosity_level, debug):
    if verbosity_level >= 1:
        print(f"Generating {_BATVM_OUT}")

    lines = read_file(_BATVM_TEMPLATE)
    num_keep_lines = 0
    num_del_lines = 0
    for k in range(len(lines)):
        line = lines[k].rstrip() + "\n"

        # Perform template substitutions.
        if line.startswith("set p="):
            prg_str = bin2str.convert(code, use_hex=True)
            line = f"set p={prg_str}\n"
        elif line.startswith("set /A ps="):
            line = f"set /A ps={len(code)}\n"

        # Perform simple minification (except for debug builds).
        if not debug:
            # We need to preserve a couple of lines after "set AX10=".
            if line.startswith("set AX10="):
                num_keep_lines = 3

            # Remove indent.
            if num_keep_lines < 1:
                line = line.lstrip()

            # Remove comments.
            line = remove_line_comment(line, start_str="REM")

            # Remove debug code and empty lines.
            if line.startswith(":WriteDebug"):
                num_del_lines = 3
            if num_del_lines > 0 or (num_keep_lines < 1 and (line.lstrip().startswith("call :WriteDebug") or line.strip() == "")):
                line = ""

            if num_keep_lines > 0:
                num_keep_lines -= 1
            if num_del_lines > 0:
                num_del_lines -= 1

        lines[k] = line.replace("\n", "\r\n")

    write_file(_BATVM_OUT, lines, make_executable=True)


def gen_c(code, verbosity_level, debug):
    if verbosity_level >= 1:
        print(f"Generating {_CVM_OUT}")

    lines = read_file(_CVM_TEMPLATE)
    for k in range(len(lines)):
        line = lines[k]

        # Perform template substitutions.
        if line.startswith("const char p[]="):
            prg_str = bin2str.convert(code, use_hex=False).replace("\\", "\\\\")
            line = f"const char p[]=\"{prg_str}\";"

        # Perform simple minification (except for debug builds).
        if not debug:
            # Remove comments.
            line = remove_line_comment(line, "//")

            # Remove indent, trailing whitespace and newlines.
            line = line.strip()

            # Remove debug code.
            if ("WriteDebug" in line):
                line = ""

            # Reinstate newline for perprocessor directives.
            if line.startswith("#"):
                line += "\n"
                if k > 0 and lines[k-1] and not lines[k-1].endswith("\n"):
                    lines[k-1] += "\n"

        lines[k] = line

    write_file(_CVM_OUT, lines, make_executable=False)


def gen_powershell(code, verbosity_level, debug):
    if verbosity_level >= 1:
        print(f"Generating {_PSVM_OUT}")

    lines = read_file(_PSVM_TEMPLATE)
    for k in range(len(lines)):
        line = lines[k]

        # Perform template substitutions.
        if line.startswith("$prg = "):
            prg_str = bin2str.convert(code, use_hex=False)
            line = f"$prg = '{prg_str}'\n"
        elif line.startswith("$DebugPreference"):
            line = '$DebugPreference = "Continue"\n' if debug else ""

        # Perform simple minification (except for debug builds).
        if not debug:
            # Remove indent.
            line = line.lstrip()

            # Remove comments (except the shebang).
            if k > 0:
                line = remove_line_comment(line)

            # Remove debug code and empty lines.
            if line.lstrip().startswith("Write-Debug") or line.strip() == "":
                line = ""

        lines[k] = line

    write_file(_PSVM_OUT, lines, make_executable=True)


def gen_python(code, verbosity_level, debug):
    if verbosity_level >= 1:
        print(f"Generating {_PYVM_OUT}")

    lines = read_file(_PYVM_TEMPLATE)
    del_lext_line = False
    for k in range(len(lines)):
        line = lines[k]

        # Perform template substitutions.
        if line.startswith("p="):
            prg_str = bin2str.convert(code, use_hex=False).replace("\\", "\\\\")
            line = f"p='{prg_str}'\n"

        # Perform simple minification (except for debug builds).
        if not debug:
            # Remove comments (except the shebang).
            if k > 0:
                line = remove_line_comment(line)

            # Remove debug code and empty lines.
            if (
                line.lstrip().startswith("WriteDebug")
                or line.strip() == ""
                or del_lext_line
            ):
                line = ""
            if line.startswith("def WriteDebug"):
                line = ""
                del_lext_line = True
            else:
                del_lext_line = False

        lines[k] = line

    write_file(_PYVM_OUT, lines, make_executable=True)


def gen_bat_frontend(verbosity_level):
    if verbosity_level >= 1:
        print(f"Generating {_BAT_FRONTEND_OUT}")

    lines = read_file(_BAT_FRONTEND_TEMPLATE)
    for k in range(len(lines)):
        lines[k] = lines[k].rstrip() + "\r\n"
    write_file(_BAT_FRONTEND_OUT, lines, make_executable=True)


def gen_sh_frontend(verbosity_level):
    if verbosity_level >= 1:
        print(f"Generating {_SH_FRONTEND_OUT}")

    lines = read_file(_SH_FRONTEND_TEMPLATE)
    for k in range(len(lines)):
        lines[k] = lines[k].rstrip() + "\n"
    write_file(_SH_FRONTEND_OUT, lines, make_executable=True)


def build(verbosity_level, debug):
    # Compile the main source.
    src_name = _REPO_ROOT / _MAIN_SOURCE
    if verbosity_level >= 1:
        print(f"Compiling {src_name}")
    code = compile_file(src_name, verbosity_level)

    # Generate the different interpreters.
    gen_bash(code, verbosity_level, debug)
    gen_bat(code, verbosity_level, debug)
    gen_c(code, verbosity_level, debug)
    gen_powershell(code, verbosity_level, debug)
    gen_python(code, verbosity_level, debug)

    # Generate the frontends.
    gen_bat_frontend(verbosity_level)
    gen_sh_frontend(verbosity_level)


def main():
    parser = argparse.ArgumentParser(description="BS build tool")
    parser.add_argument("-v", "--verbose", action="store_true", help="be verbose")
    parser.add_argument(
        "-vv", "--extra-verbose", action="store_true", help="be extra verbose"
    )
    parser.add_argument(
        "-d", "--debug", action="store_true", help="generate debug code"
    )
    args = parser.parse_args()

    # Select verbosity level.
    verbosity_level = 0
    if args.verbose:
        verbosity_level = 1
    elif args.extra_verbose:
        verbosity_level = 2

    build(verbosity_level, args.debug)


if __name__ == "__main__":
    main()
