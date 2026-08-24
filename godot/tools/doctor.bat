@echo off
rem TIDEBOUND -- project doctor for Windows.
rem
rem Double-click it, or run from cmd. There is no logic here on purpose:
rem the .bat only calls the engine, all the work stays in .gd. Duplicating it
rem in a second language would mean a second source of truth.
rem
rem Godot is looked up in PATH as "godot". If it lives elsewhere, set the path:
rem   set GODOT=C:\Godot\Godot_v4.7.2-stable_win64.exe
rem
rem ASCII only, no BOM: cmd.exe keeps reading the file by byte offset after
rem chcp changes the code page, and multi-byte text here would shift parsing.
rem chcp 65001 is for the ENGINE output, which is in Russian.
chcp 65001 >nul
if "%GODOT%"=="" set GODOT=godot

"%GODOT%" --headless --path "%~dp0.." -s res://tools/doctor.gd

rem Without pause the window closes together with the process and nobody
rem gets to read the report.
pause
