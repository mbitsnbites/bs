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
_BASH_TEMPLATE = _REPO_ROOT / "vm/bs.template.bash"
_BASH_OUT = _OUT_DIR / "bs.bash"
_PS_TEMPLATE = _REPO_ROOT / "vm/bs.template.ps1"
_PS_OUT = _OUT_DIR / "bs.ps1"
_PY_TEMPLATE = _REPO_ROOT / "vm/bs.template.py"
_PY_OUT = _OUT_DIR / "bs.py"


def read_file(name):
    lines = []
    with open(name, "r", encoding="utf8") as f:
        for line in f.readlines():
            lines.append(line)
    return lines


def write_file(name, lines, make_executable=False):
    with open(name, "w", encoding="utf8") as f:
        f.writelines(lines)

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


def remove_line_comment(line, start_char="#"):
    # TODO(m): Add support for start_char in strings.
    try:
        return line[: line.index(start_char)].rstrip() + "\n"
    except ValueError:
        return line


def gen_bash(code, verbosity_level, debug):
    if verbosity_level >= 1:
        print(f"Generating {_BASH_OUT}")

    lines = read_file(_BASH_TEMPLATE)
    for k in range(len(lines)):
        line = lines[k]

        # Perform template substitutions.
        if line.startswith("prg="):
            prg_str = bin2str.convert(code, use_hex=False)
            line = f"prg='{prg_str}'\n"

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

    write_file(_BASH_OUT, lines, make_executable=True)


def gen_powershell(code, verbosity_level, debug):
    if verbosity_level >= 1:
        print(f"Generating {_PS_OUT}")

    lines = read_file(_PS_TEMPLATE)
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

    write_file(_PS_OUT, lines, make_executable=True)


def gen_python(code, verbosity_level, debug):
    if verbosity_level >= 1:
        print(f"Generating {_PY_OUT}")

    lines = read_file(_PY_TEMPLATE)
    del_lext_line = False
    for k in range(len(lines)):
        line = lines[k]

        # Perform template substitutions.
        if line.startswith("prg="):
            prg_str = bin2str.convert(code, use_hex=False).replace("\\", "\\\\")
            line = f"prg='{prg_str}'\n"

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

    write_file(_PY_OUT, lines, make_executable=True)


def build(verbosity_level, debug):
    # Compile the main source.
    src_name = _REPO_ROOT / _MAIN_SOURCE
    if verbosity_level >= 1:
        print(f"Compiling {src_name}")
    code = compile_file(src_name, verbosity_level)

    # Generate the Bash interpreter.
    gen_bash(code, verbosity_level, debug)

    # Generate the PowerShell interpreter.
    gen_powershell(code, verbosity_level, debug)

    # Generate the Python interpreter.
    gen_python(code, verbosity_level, debug)


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
