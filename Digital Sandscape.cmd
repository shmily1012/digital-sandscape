@echo off
cd /d "%~dp0"
python run.py app
if errorlevel 1 pause
