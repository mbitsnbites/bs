@echo off
REM -*- mode: batch; tab-width: 2; indent-tabs-mode: nil; -*-
REM -----------------------------------------------------------------------------------------------
REM Copyright (c) 2020 Marcus Geelnard
REM
REM This software is provided 'as-is', without any express or implied warranty. In no event will
REM the authors be held liable for any damages arising from the use of this software.
REM
REM Permission is granted to anyone to use this software for any purpose, including commercial
REM applications, and to alter it and redistribute it freely, subject to the following
REM restrictions:
REM
REM  1. The origin of this software must not be misrepresented; you must not claim that you wrote
REM     the original software. If you use this software in a product, an acknowledgment in the
REM     product documentation would be appreciated but is not required.
REM
REM  2. Altered source versions must be plainly marked as such, and must not be misrepresented as
REM     being the original software.
REM
REM  3. This notice may not be removed or altered from any source distribution.
REM -----------------------------------------------------------------------------------------------

setlocal EnableDelayedExpansion

REM Get current script location (all VM implementations are next to it).
set d=%~dp0

REM Select the VM implementation to use (in order of preference).
call :findCmd python3
if %ERRORLEVEL% EQU 0 (
    "%c%" "%d%\bsvm.py" %*
    exit /B !ERRORLEVEL!
)

call :findCmd python
if %ERRORLEVEL% EQU 0 (
    "%c%" "%d%\bsvm.py" %*
    exit /B !ERRORLEVEL!
)

call :findCmd python2
if %ERRORLEVEL% EQU 0 (
    "%c%" "%d%\bsvm.py" %*
    exit /B !ERRORLEVEL!
)

call :findCmd powershell
if %ERRORLEVEL% EQU 0 (
    "%c%" -noprofile -executionpolicy bypass -file "%d%\bsvm.ps1" %*
    exit /B !ERRORLEVEL!
)

REM Fall back to the batch implementation (the slowest and least conformant).
"%d%\bsvm.bat" %*
exit /B !ERRORLEVEL!


:findCmd
  REM Find the file using "where".
  set cnt=0
  for /F "tokens=* usebackq" %%f in (`"where %1 2>nul"`) do (
      set c!cnt!=%%f
      set /A cnt+=1
  )
  if %cnt% EQU 0 exit /B 1
  set c=%c0%

  REM Make sure that the size is not zero (e.g. there may be some zero-sized exe:s in
  REM LOCALAPPDATA\Microsoft\WindowsApps\, such as python3.exe).
  for /F "usebackq" %%A in ('"%c%"') do set s=%%~zA
  if "%s%" == "" exit /B 1
  if "%s%" == "0" exit /B 1

  exit /B 0
