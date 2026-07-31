@echo off
cd /d "%~dp0"
echo SSD/NVMe mode: one hashing thread per logical CPU
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Utils\Find-File.ps1"
