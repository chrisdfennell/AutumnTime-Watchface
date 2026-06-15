@echo off
echo Building and running Autumn watch face in simulator...
powershell -ExecutionPolicy Bypass -File "%~dp0build.ps1" -Run
pause
