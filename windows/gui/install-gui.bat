@echo off
setlocal enabledelayedexpansion

echo =========================================================
echo 📦 Installing Cloudflare Tunnel Manager GUI (Windows)
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

REM Build app if executable missing
if not exist "%~dp0CloudflareTunnelManagerGUI.exe" (
    echo ⚙️ Building GUI application...
    call "%~dp0build.bat"
    if %ERRORLEVEL% NEQ 0 (
        echo ❌ Build failed. Aborting installation.
        pause
        exit /b 1
    )
)

echo 📁 Creating installation directory: %INSTALL_DIR%
if not exist "%INSTALL_DIR%" mkdir "%INSTALL_DIR%"

echo 🚚 Copying application files...
copy /Y "%~dp0CloudflareTunnelManagerGUI.exe" "%INSTALL_DIR%\CloudflareTunnelManagerGUI.exe" >nul
copy /Y "%~dp0uninstall-gui.bat" "%INSTALL_DIR%\uninstall-gui.bat" >nul
if exist "%~dp0..\cloudflare-tunnel-manager.ps1" (
    copy /Y "%~dp0..\cloudflare-tunnel-manager.ps1" "%INSTALL_DIR%\cloudflare-tunnel-manager.ps1" >nul
) else if exist "%~dp0cloudflare-tunnel-manager.ps1" (
    copy /Y "%~dp0cloudflare-tunnel-manager.ps1" "%INSTALL_DIR%\cloudflare-tunnel-manager.ps1" >nul
)

REM Create Start Menu & Desktop Shortcuts via PowerShell
echo 🔗 Creating Desktop and Start Menu shortcuts...
powershell -NoProfile -Command "$ws = New-Object -ComObject WScript.Shell; $s = $ws.CreateShortcut([System.IO.Path]::Combine([Environment]::GetFolderPath('Desktop'), 'Cloudflare Tunnel Manager GUI.lnk')); $s.TargetPath = '%INSTALL_DIR%\CloudflareTunnelManagerGUI.exe'; $s.WorkingDirectory = '%INSTALL_DIR%'; $s.Save()"
powershell -NoProfile -Command "$ws = New-Object -ComObject WScript.Shell; $s = $ws.CreateShortcut([System.IO.Path]::Combine([Environment]::GetFolderPath('CommonPrograms'), 'Cloudflare Tunnel Manager GUI.lnk')); $s.TargetPath = '%INSTALL_DIR%\CloudflareTunnelManagerGUI.exe'; $s.WorkingDirectory = '%INSTALL_DIR%'; $s.Save()"

REM Register in Windows Add/Remove Programs (Control Panel & Settings)
echo 📝 Registering in Windows Add/Remove Programs...
set "REG_KEY=HKLM\Software\Microsoft\Windows\CurrentVersion\Uninstall\CloudflareTunnelManagerGUI"
reg add "%REG_KEY%" /v "DisplayName" /t REG_SZ /d "Cloudflare Tunnel Manager GUI" /f >nul
reg add "%REG_KEY%" /v "DisplayVersion" /t REG_SZ /d "1.0.0" /f >nul
reg add "%REG_KEY%" /v "Publisher" /t REG_SZ /d "Dan Ong'udi" /f >nul
reg add "%REG_KEY%" /v "InstallLocation" /t REG_SZ /d "%INSTALL_DIR%" /f >nul
reg add "%REG_KEY%" /v "DisplayIcon" /t REG_SZ /d "%INSTALL_DIR%\CloudflareTunnelManagerGUI.exe,0" /f >nul
reg add "%REG_KEY%" /v "UninstallString" /t REG_SZ /d "cmd.exe /c \"%INSTALL_DIR%\uninstall-gui.bat\"" /f >nul

echo.
echo =========================================================
echo ✅ INSTALLATION COMPLETE!
echo 🚀 Cloudflare Tunnel Manager GUI has been installed to:
echo    %INSTALL_DIR%\CloudflareTunnelManagerGUI.exe
echo.
echo 📌 Shortcuts created on Desktop and Start Menu.
echo 📌 Registered in Windows Settings > Installed Apps.
echo =========================================================
pause
