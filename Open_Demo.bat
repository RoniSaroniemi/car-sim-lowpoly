@echo off
cd /d "%~dp0"
py -3 tools\demo.py run %*
if errorlevel 1 pause
