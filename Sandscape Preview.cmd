@echo off
cd /d "%~dp0"
python run.py sandscape-preview
if errorlevel 1 pause
