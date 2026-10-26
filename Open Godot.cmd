@echo off
setlocal
set "GODOT_EXE=D:\Install\Godot_v4.4.1-stable_win64.exe\Godot_v4.4.1-stable_win64.exe"
if not exist "%GODOT_EXE%" (
    echo Godot executable not found: %GODOT_EXE%
    pause
    exit /b 1
)
start "" "%GODOT_EXE%" --editor --single-window --rendering-method forward_plus --rendering-driver vulkan --path "%~dp0."
if errorlevel 1 pause
