@echo off
:: Cloudflare Tunnel Manager - Windows Launcher
:: Double-click this file or run from Command Prompt to start the manager.
:: Automatically requests Administrator privileges (UAC prompt).

title Cloudflare Tunnel Manager (Windows)

:: Check for Administrator privileges, auto-elevate if not running as Admin
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo ==============================================================================
    echo  Requesting Administrator privileges...
    echo  Please click 'Yes' on the Windows UAC prompt to continue.
    echo ==============================================================================
    powershell -Command "Start-Process cmd.exe -ArgumentList '/c \"\"%~f0\"\"' -Verb RunAs"
    exit /b
)

powershell -ExecutionPolicy Bypass -NoProfile -File "%~dp0cloudflare-tunnel-manager.ps1"
pause
