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


_BIN2CHAR = "()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefg"


def convert(bin_data):
    if len(bin_data) % 2 == 1:
        bin_data += b"\0"

    result = ""
    for i in range(len(bin_data) // 2):
        b1 = bin_data[2 * i]
        b2 = bin_data[2 * i + 1]
        c1 = _BIN2CHAR[b1 >> 2]
        c2 = _BIN2CHAR[((b1 & 3) << 3) | (b2 >> 5)]
        c3 = _BIN2CHAR[(b2 & 31)]
        result += c1 + c2 + c3

    return result


def main():
    parser = argparse.ArgumentParser(description="Convert binary file to a string")
    parser.add_argument(
        "--3b2c", action="store_true", help="use format: 3 bytes per 2 characters"
    )
    parser.add_argument("infile", help="input file")
    parser.add_argument("outfile", help="output file")
    args = parser.parse_args()

    with open(args.infile, "rb") as f:
        in_data = f.read()

    str_data = convert(in_data)

    with open(args.outfile, "w", encoding="utf8") as f:
        f.write(str_data)


if __name__ == "__main__":
    main()
