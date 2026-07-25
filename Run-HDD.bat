@echo off
cd /d "%~dp0"
echo HDD mode: 2 hashing threads
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Utils\Find-File.ps1" -Threads 2
