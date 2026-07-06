@echo off
:: Cloudflare Tunnel Manager - Windows Launcher
:: Double-click this file or run from Command Prompt to start the manager.
:: Requires PowerShell 5.1+ (included with Windows 10/11).

powershell -ExecutionPolicy Bypass -NoProfile -File "%~dp0cloudflare-tunnel-manager.ps1"
pause
