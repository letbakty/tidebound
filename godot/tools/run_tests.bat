@echo off
rem TIDEBOUND -- test run for Windows.
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

rem An argument filters suites by substring: run_tests.bat production
"%GODOT%" --headless --path "%~dp0.." -s res://tests/run_all.gd -- %*
rem NOTE: unlike run_tests.sh there is no second line of defence here -- the
rem .sh greps the log for SCRIPT ERROR because GDScript cannot see engine
rem errors. On Windows read the log yourself: any SCRIPT ERROR or ERROR: line
rem above is a defect even when the report is green.

rem Without pause the window closes together with the process and nobody
rem gets to read the report.
pause
