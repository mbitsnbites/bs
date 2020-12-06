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
_BIN2HEX = "0123456789ABCDEF"


def to3cp2b(bin_data):
    result = ""
    for i in range(len(bin_data) // 2):
        b1 = bin_data[2 * i]
        b2 = bin_data[2 * i + 1]
        c1 = _BIN2CHAR[b1 >> 2]
        c2 = _BIN2CHAR[((b1 & 3) << 3) | (b2 >> 5)]
        c3 = _BIN2CHAR[(b2 & 31)]
        result += c1 + c2 + c3
    return result


def tohex(bin_data):
    result = ""
    for i in range(len(bin_data)):
        b = bin_data[i]
        c1 = _BIN2HEX[b >> 4]
        c2 = _BIN2HEX[b & 15]
        result += c1 + c2
    return result


def convert(bin_data, use_hex):
    if len(bin_data) % 2 == 1:
        bin_data += b"\0"

    if use_hex:
        return tohex(bin_data)
    else:
        return to3cp2b(bin_data)


def main():
    parser = argparse.ArgumentParser(description="Convert binary file to a string")
    parser.add_argument("--hex", action="store_true", help="use hex format")
    parser.add_argument("infile", help="input file")
    parser.add_argument("outfile", help="output file")
    args = parser.parse_args()

    with open(args.infile, "rb") as f:
        in_data = f.read()

    str_data = convert(in_data, use_hex=args.hex)

    with open(args.outfile, "w", encoding="utf8") as f:
        f.write(str_data)


if __name__ == "__main__":
    main()
