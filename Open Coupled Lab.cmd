@echo off
pushd "%~dp0"
python run.py coupled-lab
if errorlevel 1 pause
popd
