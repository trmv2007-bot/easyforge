@echo off
REM ============================================================
REM  EasyForge launcher — one double-click, no install, no admin.
REM  Runs the portable Godot build that ships in tools/.
REM ============================================================
cd /d "%~dp0"

set GODOT=tools\Godot_v4.7.2-stable_win64.exe

if not exist "%GODOT%" (
    echo.
    echo  [ERROR] Godot build not found at %GODOT%
    echo  The app needs its tools\ folder. Do not move Godot out of it.
    echo.
    pause
    exit /b 1
)

echo  Starting EasyForge...
start "" "%GODOT%" --path "%~dp0" res://src/ui/main.tscn
