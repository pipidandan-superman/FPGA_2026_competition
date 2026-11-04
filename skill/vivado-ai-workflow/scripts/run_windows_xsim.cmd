@echo off
setlocal
if "%~3"=="" echo usage: run_windows_xsim.cmd WORK_DIR TOP PASS_MARKER SOURCE... & exit /b 2
if "%~4"=="" echo usage: run_windows_xsim.cmd WORK_DIR TOP PASS_MARKER SOURCE... & exit /b 2
set SystemRoot=C:\Windows
set COMSPEC=C:\Windows\System32\cmd.exe
set PROCESSOR_ARCHITECTURE=AMD64
set XILINX_VIVADO=F:\vivado2025\2025.2\Vivado
set PATH=C:\Windows\System32;C:\Windows;F:\vivado2025\2025.2\Vivado\bin;F:\vivado2025\2025.2\Vivado\lib\win64.o
set B=F:\vivado2025\2025.2\Vivado\bin
set WORK=%~1
set TOP=%~2
set MARKER=%~3
shift
shift
shift
set SOURCES=
:collect
if "%~1"=="" goto run
set SOURCES=%SOURCES% "%~1"
shift
goto collect
:run
cd /d "%WORK%" || exit /b 1
call "%B%\xvlog.bat" %SOURCES% > "%TOP%_xvlog.log" 2>&1 || exit /b 1
call "%B%\xelab.bat" work.%TOP% -debug off > "%TOP%_xelab.log" 2>&1 || exit /b 1
call "%B%\xsim.bat" work.%TOP% -R > "%TOP%_xsim.log" 2>&1 || exit /b 1
findstr /C:"%MARKER%" "%TOP%_xsim.log" || exit /b 1
exit /b 0
