@echo off
cd /d "%~dp0.."
powershell.exe -ExecutionPolicy Bypass -File "%~dp0start_preview.ps1"
pause
