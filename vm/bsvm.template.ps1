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

$DebugPreference="Continue"  # DON'T MODIFY THIS LINE! IT IS REPLACED BY THE BUILD PROCESS!

# Define the BS VM program. We use a packed string (3 characters per 2 bytes).
$p="?((((("  # DON'T MODIFY THIS LINE! IT IS REPLACED BY THE BUILD PROCESS!

class VM {
  # Constants.
  [Int32]$_EQ=1
  [Int32]$_LT=2
  [Int32]$_LE=3  # _LT | _EQ
  [Int32]$_GT=4
  [Int32]$_GE=5  # _GT | _EQ

  # Instruction operand configuration (one element per instruction).
  #
  #  * nout - Number of output (or in/out) register operands.
  #  * ninr - Number of input register operands.
  #  * ninx - Number of "final" input operands (any operand kind).
  #
  # OP:                             1 1 1 1 1 1 1 1 1 1 2 2 2 2 2 2 2 2 2 2 3 3
  #             0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
  [Byte[]]$nout=0,1,1,1,0,0,0,0,0,0,0,0,0,0,0,0,0,1,1,1,1,1,1,1,1,1,1,1,0,0,0,0
  [Byte[]]$ninr=0,0,1,1,2,2,0,0,0,0,0,0,0,0,0,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
  [Byte[]]$ninx=0,1,1,1,1,1,1,1,0,1,1,1,1,1,1,1,1,0,1,1,1,1,1,1,1,1,1,1,1,1,1,1

  # Memory.
  [Byte[]]$m

  [Int32]getI([Int32]$addr){
    return ([Int32]$this.m[$addr]) -bor (([Int32]$this.m[$addr+1]) -shl 8) -bor (([Int32]$this.m[$addr+2]) -shl 16) -bor (([Int32]$this.m[$addr+3]) -shl 24)
  }

  [void]setI([Int32]$addr,[Int32]$value){
    $this.m[$addr]=[Byte]($value -band 255)
    $this.m[$addr+1]=[Byte](($value -shr 8) -band 255)
    $this.m[$addr+2]=[Byte](($value -shr 16) -band 255)
    $this.m[$addr+3]=[Byte](($value -shr 24) -band 255)
  }

  [string]getS([Int32]$addr){
    [Int32]$num_bytes=$this.getI($addr)
    $first=$addr+4
    $str_len=[System.Text.Encoding]::UTF8.GetCharCount($this.m,$first,$num_bytes)
    [char[]]$utf8_chars=New-Object char[] $str_len;
    [System.Text.Encoding]::UTF8.GetChars($this.m,$first,$num_bytes,$utf8_chars,0);
    return -join $utf8_chars
  }

  [Int32]run([String]$p){
    # Initialize the memory.
    $this.m=New-Object Byte[] 1048576  # 1 MiB

    # Set the startup execution state.
    [Int32]$pc=1
    [Int32]$cc=0
    [Int32[]]$r=New-Object Int32[] 256

    # Convert the packed string to bytes and store it in the memory.
    $prg_size=($p.Length*2)/3
    Write-Debug("prg_size={0}" -f $prg_size)
    for($i=0;$i -lt ($prg_size/2);$i++){
      $c1=[Byte]($p.Chars($i*3))-40    # 6 bits (0-63)
      $c2=[Byte]($p.Chars($i*3+1))-40  # 5 bits (0-31)
      $c3=[Byte]($p.Chars($i*3+2))-40  # 5 bits (0-31)
      $b1=($c1 -shl 2) -bor ($c2 -shr 3)
      $b2=(($c2 -band 7) -shl 5) -bor $c3
      $this.m[$i*2+1]=$b1
      $this.m[$i*2+2]=$b2
      Write-Debug("(c1,c2,c3)=({0},{1},{2}) -> ({3},{4})" -f $c1,$c2,$c3,$b1,$b2)
    }

    # Main execution loop.
    [Int32]$exit_code=1
    [boolean]$running=$true
    while($running){
      # Read the next opcode.
      $pc0=$pc
      $op0=$this.m[$pc++]

      # Decode the opcode:
      #   Bits 0-5: operation
      #   Bits 6-7: argument type
      $at=$op0 -shr 6
      $op=$op0 -band 63

      Write-Debug("PC={0} CC={1} OP={2} OP*={3} AT={4}" -f $pc0,$cc,$op0,$op,$at)

      # Read the operands.
      $o=@()
      if($this.nout[$op] -eq 1){
        # Get register number (0-255)
        $o+=[Int32]$this.m[$pc++]
      }
      $n=$pc+$this.ninr[$op]
      while($pc -lt $n){
        # Get register value
        $o+=$r[$this.m[$pc++]]
      }
      if($this.ninx[$op] -eq 1){
        if($at -eq 3){
          # 32-bit immediate.
          $b0=[Int32]$this.m[$pc]
          $b1=[Int32]$this.m[$pc+1]
          $b2=[Int32]$this.m[$pc+2]
          $b3=[Int32]$this.m[$pc+3]
          $v=$b0 -bor ($b1 -shl 8) -bor ($b2 -shl 16) -bor ($b3 -shl 24)
          $pc+=4
        }else{
          # Arg types 0-2 use a single byte.
          $v=[Int32]$this.m[$pc++]

          if($at -eq 0){
            # Register value.
            $v=$r[$v]
          }else{
            # Convert unsigned to signed byte (-128..127).
            if($v -gt 127){$v=$v-256}

            if($at -eq 2){$v+=$pc0} # 8-bit PC-relative offset.
            # else $v=$v ($at=1, 8-bit signed immedate)
          }
        }
        $o+=$v
      }

      switch($op){
        1{ # MOV
          Write-Debug("MOV R{0}, {1}" -f $o[0],$o[1])
          $r[$o[0]]=$o[1]
        }

        2{ # LDB
          Write-Debug("LDB R{0}, {1}, {2}" -f $o[0],$o[1],$o[2])
          $r[$o[0]]=[Int32]$this.m[$o[1]+$o[2]]
        }

        3{ # LDW
          Write-Debug("LDW R{0}, {1}, {2}" -f $o[0],$o[1],$o[2])
          $r[$o[0]]=$this.getI($o[1]+$o[2])
        }

        4{ # STB
          Write-Debug("STB {0}, {1}, {2}" -f $o[0],$o[1],$o[2])
          $this.m[$o[1]+$o[2]]=$o[0] -band 255
        }

        5{ # STW
          Write-Debug("STW {0}, {1}, {2}" -f $o[0],$o[1],$o[2])
          $this.setI($o[1]+$o[2],$o[0])
        }

        6{ # JMP
          Write-Debug("JMP {0}" -f $o[0])
          $pc=$o[0]
        }

        7{ # JSR
          Write-Debug("JSR {0}" -f $o[0])
          $r[255]-=4
          $this.setI($r[255],$pc)
          $pc=$o[0]
        }

        8{ # RTS
          Write-Debug("RTS")
          $pc=$this.getI($r[255])
          $r[255]+=4
        }

        9{ # BEQ
          Write-Debug("BEQ {0}" -f $o[0])
          if(($cc -band $this._EQ) -ne 0){$pc=$o[0]}
        }

        10{ # BNE
          Write-Debug("BNE {0}" -f $o[0])
          if(($cc -band $this._EQ) -eq 0){$pc=$o[0]}
        }

        11{ # BLT
          Write-Debug("BLT {0}" -f $o[0])
          if(($cc -band $this._LT) -ne 0){$pc=$o[0]}
        }

        12{ # BLE
          Write-Debug("BLE {0}" -f $o[0])
          if(($cc -band $this._LE) -ne 0){$pc=$o[0]}
        }

        13{ # BGT
          Write-Debug("BGT {0}" -f $o[0])
          if(($cc -band $this._GT) -ne 0){$pc=$o[0]}
        }

        14{ # BGE
          Write-Debug("BGE {0}" -f $o[0])
          if(($cc -band $this._GE) -ne 0){$pc=$o[0]}
        }

        15{ # CMP
          Write-Debug("CMP {0}, {1}" -f $o[0],$o[1])
          $new_cc=0
          if($o[0] -eq $o[1]){$new_cc=$this._EQ}
          if($o[0] -lt $o[1]){$new_cc=$new_cc -bor $this._LT}
          if($o[0] -gt $o[1]){$new_cc=$new_cc -bor $this._GT}
          $cc=$new_cc
        }

        16{ # PUSH
          Write-Debug("PUSH {0}" -f $o[0])
          $r[255]-=4
          $this.setI($r[255],$o[0])
        }

        17{ # POP
          Write-Debug("POP R{0}" -f $o[0])
          $r[$o[0]]=$this.getI($r[255])
          $r[255]+=4
        }

        18{ # ADD
          Write-Debug("ADD R{0}, {1}" -f $o[0],$o[1])
          $r[$o[0]]+=$o[1]
        }

        19{ # SUB
          Write-Debug("SUB R{0}, {1}" -f $o[0],$o[1])
          $r[$o[0]]-=$o[1]
        }

        20{ # MUL
          Write-Debug("MUL R{0}, {1}" -f $o[0],$o[1])
          $r[$o[0]]*=$o[1]
        }

        21{ # DIV
          Write-Debug("DIV R{0}, {1}" -f $o[0],$o[1])
          $r[$o[0]]/=$o[1]
        }

        22{ # MOD
          Write-Debug("MOD R{0}, {1}" -f $o[0],$o[1])
          $r[$o[0]]%=$o[1]
        }

        23{ # AND
          Write-Debug("AND R{0}, {1}" -f $o[0],$o[1])
          $r[$o[0]]=$r[$o[0]] -band $o[1]
        }

        24{ # OR
          Write-Debug("OR R{0}, {1}" -f $o[0],$o[1])
          $r[$o[0]]=$r[$o[0]] -bor $o[1]
        }

        25{ # XOR
          Write-Debug("XOR R{0}, {1}" -f $o[0],$o[1])
          $r[$o[0]]=$r[$o[0]] -bxor $o[1]
        }

        26{ # SHL
          Write-Debug("SHL R{0}, {1}" -f $o[0],$o[1])
          $r[$o[0]]=$r[$o[0]] -shl $o[1]
        }

        27{ # SHR
          Write-Debug("SHR R{0}, {1}" -f $o[0],$o[1])
          $r[$o[0]]=$r[$o[0]] -shr $o[1]
        }

        28{ # EXIT
          Write-Debug("EXIT {0}" -f $o[0])
          $exit_code=$o[0]
          $running=$false
        }

        29{ # PRINTLN
          $str=$this.getS($o[0])
          Write-Debug("PRINTLN {0} ({1})" -f $o[0],$str)
          Write-Host $str
        }

        30{ # PRINT
          $str=$this.getS($o[0])
          Write-Debug("PRINT {0} ({1})" -f $o[0],$str)
          Write-Host $str -NoNewline
        }

        31{ # RUN
          $str=$this.getS($o[0])
          Write-Debug("RUN {0} ({1})" -f $o[0],$str)
          $c=$str.Split(" ")[0]
          $a=$str.Substring($c.Length+1).TrimStart()
          Start-Process -Wait -FilePath $c -ArgumentList $a
        }

        default {
          Write-Debug("Unsupported op={0} @ pc={1}" -f $op, $pc)
          $running=$false
        }
      }
    }

    return $exit_code
  }
}

[VM]$vm=[VM]::new()
exit $vm.run($p)
