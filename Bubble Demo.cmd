@echo off
cd /d "%~dp0"
python run.py bubble-demo
if errorlevel 1 pause
