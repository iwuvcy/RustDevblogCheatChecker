@echo off
cd /d "%~dp0"
echo SSD/NVMe mode: 12 hashing threads
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Utils\Find-File.ps1" -Threads 12
