@echo off
if not defined BOARD_PYTHON exit /b 1
"%BOARD_PYTHON%" "%~dp0ssh_askpass.py"
