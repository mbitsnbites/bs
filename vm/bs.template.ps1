#!/usr/bin/env powershell
# -*- mode: powershell; tab-width: 2; indent-tabs-mode: nil; -*-
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

$DebugPreference = "DON'T MODIFY THIS LINE! IT IS REPLACED BY THE BUILD PROCESS!"

# Define the BS VM program. We use a packed string (3 characters per 2 bytes).
$prg = "DON'T MODIFY THIS LINE! IT IS REPLACED BY THE BUILD PROCESS!"

class VM {
  # Constants.
  [Int32]$_CC_EQ = 1
  [Int32]$_CC_LT = 2
  [Int32]$_CC_GT = 4

  # RAM.
  [Byte[]]$ram
  [Int32]$ram_size

  # Execution state.
  [Int32]$pc
  [Int32]$instrPC
  [Int32]$cc
  [Int32[]]$reg

  VM([string]$prg) {
    # Initialize the RAM.
    $this.ram_size = 1048576  # 1 MiB
    $this.ram = New-Object Byte[] $this.ram_size

    # Set the startup execution state.
    $this.pc = 0
    $this.cc = 0
    $this.reg = New-Object Int32[] 256

    # Convert the packed string to bytes and store it in the RAM,
    # starting at address $00000000.
    $prg_size = ($prg.Length * 2) / 3
    Write-Debug ("prg_size={0}" -f $prg_size)
    for ($i = 0; $i -lt ($prg_size/2); $i++) {
      $c1 = [Byte]($prg.Chars($i*3))-40    # 6 bits (0-63)
      $c2 = [Byte]($prg.Chars($i*3+1))-40  # 5 bits (0-31)
      $c3 = [Byte]($prg.Chars($i*3+2))-40  # 5 bits (0-31)
      $b1 = ($c1 -shl 2) -bor ($c2 -shr 3)
      $b2 = (($c2 -band 7) -shl 5) -bor $c3
      $this.ram[$i*2] = $b1
      $this.ram[$i*2+1] = $b2
      Write-Debug ("(c1,c2,c3)=({0},{1},{2}) -> ({3},{4})" -f $c1,$c2,$c3,$b1,$b2)
    }
  }

  [Byte]getByte([Int32]$addr) {
    return $this.ram[$addr]
  }

  [void]setByte([Int32]$addr, [Byte]$value) {
    $this.ram[$addr] = $value
  }

  [Int32]getInt32([Int32]$addr) {
    return ([Int32]$this.ram[$addr]) -bor (([Int32]$this.ram[$addr+1]) -shl 8) -bor (([Int32]$this.ram[$addr+2]) -shl 16) -bor (([Int32]$this.ram[$addr+3]) -shl 24)
  }

  [void]setInt32([Int32]$addr, [Int32]$value) {
    $this.ram[$addr] = [Byte]($value -band 255)
    $this.ram[$addr + 1] = [Byte](($value -shr 8) -band 255)
    $this.ram[$addr + 2] = [Byte](($value -shr 16) -band 255)
    $this.ram[$addr + 3] = [Byte](($value -shr 24) -band 255)
  }

  [string]getString([Int32]$addr) {
    [Int32]$num_bytes = $this.getInt32($addr)
    $first = $addr + 4
    $str_len = [System.Text.Encoding]::UTF8.GetCharCount($this.ram, $first, $num_bytes)
    [char[]]$utf8_chars = New-Object char[] $str_len;
    [System.Text.Encoding]::UTF8.GetChars($this.ram, $first, $num_bytes, $utf8_chars, 0);
    return -join $utf8_chars
  }

  [Int32]getUint8PC() {
    $this.pc++
    return $this.getByte($this.pc - 1)
  }

  [Int32]getRegPC() {
    return $this.reg[$this.getUint8PC()]
  }

  [Int32]getOperandPC($arg_type) {
    # 32-bit immediate.
    if ($arg_type -eq 3) {
      $this.pc += 4
      return $this.getInt32($this.pc - 4)
    }

    # Arg types 0-2 use a single byte.
    [Int32]$value = [Int32]$this.getByte($this.pc)
    $this.pc++

    # Register value.
    if ($arg_type -eq 0) {
      return $this.reg[$value]
    }

    # Convert unsigned to signed byte (-128..127).
    if ($value -gt 127) { $value = $value - 256 }

    # 8-bit signed immedate.
    if ($arg_type -eq 1) {
      return $value
    }

    # 8-bit PC-relative offset (arg_type = 2).
    return $this.instrPC + $value
  }

  [void]pushInt32([Int32]$x) {
    # R255 is SP
    $this.reg[255] -= 4
    $this.setInt32($this.reg[255], $x)
  }

  [Int32]popInt32() {
    # R255 is SP
    $x = $this.getInt32($this.reg[255])
    $this.reg[255] += 4
    return $x
  }

  [Int32]run() {
    [Int32]$exit_code = 1
    [boolean]$running = $true
    while ($running) {
      # Read the next opcode.
      $this.instrPC = $this.pc
      $op = $this.getUint8PC()

      # Decode the opcode:
      #   Bits 0-5: operation
      #   Bits 6-7: argument type
      $arg_type = $op -shr 6
      $operation = $op -band 63

      Write-Debug ("PC={0} CC={1} OP={2} OP*={3} AT={4}" -f $this.instrPC, $this.cc, $op, $operation, $arg_type)

      switch ($operation) {
        1 { # MOV
          [Int32]$op1 = $this.getUint8PC()
          [Int32]$op2 = $this.getOperandPC($arg_type)
          Write-Debug ("MOV R{0}, {1}" -f $op1, $op2)
          $this.reg[$op1] = $op2
        }

        2 { # LDB
          [Int32]$op1 = $this.getUint8PC()
          [Int32]$op2 = $this.getRegPC()
          [Int32]$op3 = $this.getOperandPC($arg_type)
          Write-Debug ("LDB R{0}, {1}, {2}" -f $op1, $op2, $op3)
          $this.reg[$op1] = [Int32]$this.getByte($op2+$op3)
        }

        3 { # LDW
          [Int32]$op1 = $this.getUint8PC()
          [Int32]$op2 = $this.getRegPC()
          [Int32]$op3 = $this.getOperandPC($arg_type)
          Write-Debug ("LDW R{0}, {1}, {2}" -f $op1, $op2, $op3)
          $this.reg[$op1] = $this.getInt32($op2+$op3)
        }

        4 { # STB
          [Int32]$op1 = $this.getRegPC()
          [Int32]$op2 = $this.getRegPC()
          [Int32]$op3 = $this.getOperandPC($arg_type)
          Write-Debug ("STB {0}, {1}, {2}" -f $op1, $op2, $op3)
          $this.setByte($op2+$op3, [Byte]($op1 -band 255))
        }

        5 { # STW
          [Int32]$op1 = $this.getRegPC()
          [Int32]$op2 = $this.getRegPC()
          [Int32]$op3 = $this.getOperandPC($arg_type)
          Write-Debug ("STW {0}, {1}, {2}" -f $op1, $op2, $op3)
          $this.setInt32($op2+$op3, $op1)
        }

        6 { # JMP
          [Int32]$op1 = $this.getOperandPC($arg_type)
          Write-Debug ("JMP {0}" -f $op1)
          $this.pc = $op1
        }

        7 { # JSR
          [Int32]$op1 = $this.getOperandPC($arg_type)
          Write-Debug ("JSR {0}" -f $op1)
          $this.pushInt32($this.pc)
          $this.pc = $op1
        }

        8 { # RTS
          Write-Debug ("RTS")
          $this.pc = $this.popInt32()
        }

        9 { # BEQ
          [Int32]$op1 = $this.getOperandPC($arg_type)
          Write-Debug ("BEQ {0}" -f $op1)
          if (($this.cc -band $this._CC_EQ) -ne 0) { $this.pc = $op1 }
        }

        10 { # BNE
          [Int32]$op1 = $this.getOperandPC($arg_type)
          Write-Debug ("BNE {0}" -f $op1)
          if (($this.cc -band $this._CC_EQ) -eq 0) { $this.pc = $op1 }
        }

        11 { # BLT
          [Int32]$op1 = $this.getOperandPC($arg_type)
          Write-Debug ("BLT {0}" -f $op1)
          if (($this.cc -band $this._CC_LT) -ne 0) { $this.pc = $op1 }
        }

        12 { # BLE
          [Int32]$op1 = $this.getOperandPC($arg_type)
          Write-Debug ("BLE {0}" -f $op1)
          if ((($this.cc -band $this._CC_LT) -ne 0) -or (($this.cc -band $this._CC_EQ) -ne 0)) { $this.pc = $op1 }
        }

        13 { # BGT
          [Int32]$op1 = $this.getOperandPC($arg_type)
          Write-Debug ("BGT {0}" -f $op1)
          if (($this.cc -band $this._CC_GT) -ne 0) { $this.pc = $op1 }
        }

        14 { # BGE
          [Int32]$op1 = $this.getOperandPC($arg_type)
          Write-Debug ("BGE {0}" -f $op1)
          if ((($this.cc -band $this._CC_GT) -ne 0) -or (($this.cc -band $this._CC_EQ) -ne 0)) { $this.pc = $op1 }
        }

        15 { # CMP
          [Int32]$op1 = $this.getRegPC()
          [Int32]$op2 = $this.getOperandPC($arg_type)
          Write-Debug ("CMP {0}, {1}" -f $op1, $op2)
          $new_cc = 0
          if ($op1 -eq $op2) { $new_cc = $new_cc -bor $this._CC_EQ }
          if ($op1 -lt $op2) { $new_cc = $new_cc -bor $this._CC_LT }
          if ($op1 -gt $op2) { $new_cc = $new_cc -bor $this._CC_GT }
          $this.cc = $new_cc
        }

        16 { # PUSH
          [Int32]$op1 = $this.getOperandPC($arg_type)
          Write-Debug ("PUSH {0}" -f $op1)
          $this.pushInt32($op1)
        }

        17 { # POP
          [Int32]$op1 = $this.getUint8PC()
          Write-Debug ("POP R{0}" -f $op1)
          $this.reg[$op1] = $this.popInt32()
        }

        18 { # ADD
          [Int32]$op1 = $this.getUint8PC()
          [Int32]$op2 = $this.getOperandPC($arg_type)
          Write-Debug ("ADD R{0}, {1}" -f $op1, $op2)
          $this.reg[$op1] += $op2
        }

        19 { # SUB
          [Int32]$op1 = $this.getUint8PC()
          [Int32]$op2 = $this.getOperandPC($arg_type)
          Write-Debug ("SUB R{0}, {1}" -f $op1, $op2)
          $this.reg[$op1] -= $op2
        }

        20 { # MUL
          [Int32]$op1 = $this.getUint8PC()
          [Int32]$op2 = $this.getOperandPC($arg_type)
          Write-Debug ("MUL R{0}, {1}" -f $op1, $op2)
          $this.reg[$op1] *= $op2
        }

        21 { # DIV
          [Int32]$op1 = $this.getUint8PC()
          [Int32]$op2 = $this.getOperandPC($arg_type)
          Write-Debug ("DIV R{0}, {1}" -f $op1, $op2)
          $this.reg[$op1] /= $op2
        }

        22 { # MOD
          [Int32]$op1 = $this.getUint8PC()
          [Int32]$op2 = $this.getOperandPC($arg_type)
          Write-Debug ("MOD R{0}, {1}" -f $op1, $op2)
          $this.reg[$op1] %= $op2
        }

        23 { # AND
          [Int32]$op1 = $this.getUint8PC()
          [Int32]$op2 = $this.getOperandPC($arg_type)
          Write-Debug ("AND R{0}, {1}" -f $op1, $op2)
          $this.reg[$op1] = $this.reg[$op1] -band $op2
        }

        24 { # OR
          [Int32]$op1 = $this.getUint8PC()
          [Int32]$op2 = $this.getOperandPC($arg_type)
          Write-Debug ("OR R{0}, {1}" -f $op1, $op2)
          $this.reg[$op1] = $this.reg[$op1] -bor $op2
        }

        25 { # XOR
          [Int32]$op1 = $this.getUint8PC()
          [Int32]$op2 = $this.getOperandPC($arg_type)
          Write-Debug ("XOR R{0}, {1}" -f $op1, $op2)
          $this.reg[$op1] = $this.reg[$op1] -bxor $op2
        }

        26 { # SHL
          [Int32]$op1 = $this.getUint8PC()
          [Int32]$op2 = $this.getOperandPC($arg_type)
          Write-Debug ("SHL R{0}, {1}" -f $op1, $op2)
          $this.reg[$op1] = $this.reg[$op1] -shl $op2
        }

        27 { # SHR
          [Int32]$op1 = $this.getUint8PC()
          [Int32]$op2 = $this.getOperandPC($arg_type)
          Write-Debug ("SHR R{0}, {1}" -f $op1, $op2)
          $this.reg[$op1] = $this.reg[$op1] -shr $op2
        }

        28 { # EXIT
          [Int32]$op1 = $this.getOperandPC($arg_type)
          Write-Debug ("EXIT {0}" -f $op1)
          $exit_code = $op1
          $running = $false
        }

        29 { # PRINTLN
          [Int32]$op1 = $this.getOperandPC($arg_type)
          $str = $this.getString($op1)
          Write-Debug ('PRINTLN {0} ("{1}")' -f $op1,$str)
          Write-Host $str
        }

        30 { # PRINT
          [Int32]$op1 = $this.getOperandPC($arg_type)
          $str = $this.getString($op1)
          Write-Debug ('PRINT {0} ("{1}")' -f $op1,$str)
          Write-Host $str -NoNewline
        }

        31 { # RUN
          [Int32]$op1 = $this.getOperandPC($arg_type)
          $str = $this.getString($op1)
          Write-Debug ('RUN {0} ("{1}")' -f $op1,$str)
          $c = $str.Split(" ")[0]
          $a = $str.Substring($c.Length+1).TrimStart()
          Start-Process -Wait -FilePath $c -ArgumentList $a
        }

        default {
          Write-Warning ("Unsupported op={0} @ pc={1}" -f $op, $this.pc)
          $running = $false
        }
      }
    }

    return $exit_code
  }
}

[VM]$vm = [VM]::new($prg)
exit $vm.run()

