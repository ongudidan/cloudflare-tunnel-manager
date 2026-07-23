@echo off
setlocal enabledelayedexpansion

echo =========================================================
echo 🗑️ Uninstalling Cloudflare Tunnel Manager GUI (Windows)
echo =========================================================

REM Check Administrator
net session >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo 🔒 Administrator privileges required.
    echo ⚡ Requesting elevation...
    powershell -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

set "INSTALL_DIR=C:\Program Files\Cloudflare Tunnel Manager"

echo 🛑 Stopping any running instances...
taskkill /F /IM CloudflareTunnelManagerGUI.exe >nul 2>&1

echo 🔗 Removing Desktop and Start Menu shortcuts...
powershell -NoProfile -Command "$desktop = [Environment]::GetFolderPath('Desktop'); $s1 = [System.IO.Path]::Combine($desktop, 'Cloudflare Tunnel Manager GUI.lnk'); if (Test-Path $s1) { Remove-Item $s1 -Force }"
powershell -NoProfile -Command "$programs = [Environment]::GetFolderPath('CommonPrograms'); $s2 = [System.IO.Path]::Combine($programs, 'Cloudflare Tunnel Manager GUI.lnk'); if (Test-Path $s2) { Remove-Item $s2 -Force }"

echo 📝 Removing Add/Remove Programs registry entry...
reg delete "HKLM\Software\Microsoft\Windows\CurrentVersion\Uninstall\CloudflareTunnelManagerGUI" /f >nul 2>&1

echo 🧹 Removing installation files...
if exist "%INSTALL_DIR%" (
    rmdir /S /Q "%INSTALL_DIR%" >nul 2>&1
)

echo.
echo =========================================================
echo ✅ UNINSTALLATION COMPLETE!
echo 🗑️ Cloudflare Tunnel Manager GUI has been removed.
echo =========================================================
pause
