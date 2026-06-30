@echo off
REM Simple wrapper for native Windows. Requires PowerShell and GCC from MSYS2/MinGW-w64.
REM Usage: run_all_windows.bat native_windows
set ENVNAME=%1
if "%ENVNAME%"=="" set ENVNAME=native_windows
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0run_all_windows.ps1" -EnvironmentName "%ENVNAME%"
pause
