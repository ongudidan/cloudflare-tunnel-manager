@echo off
setlocal enabledelayedexpansion

echo =========================================================
echo 🔨 Building Cloudflare Tunnel Manager GUI (C++)
echo =========================================================

set "GUI_DIR=%~dp0"
if "%GUI_DIR:~-1%"=="\" set "GUI_DIR=%GUI_DIR:~0,-1%"

REM Locate C++ compiler
set "COMPILER="
set "WINDRES="

where x86_64-w64-mingw32-clang++ >nul 2>&1
if %ERRORLEVEL% == 0 (
    set "COMPILER=x86_64-w64-mingw32-clang++"
    set "WINDRES=llvm-windres"
    goto FOUND_COMPILER
)

where g++ >nul 2>&1
if %ERRORLEVEL% == 0 (
    set "COMPILER=g++"
    set "WINDRES=windres"
    goto FOUND_COMPILER
)

where clang++ >nul 2>&1
if %ERRORLEVEL% == 0 (
    set "COMPILER=clang++"
    set "WINDRES=llvm-windres"
    goto FOUND_COMPILER
)

for /f "delims=" %%F in ('dir /b /s "C:\Users\%USERNAME%\AppData\Local\Microsoft\WinGet\Packages\*x86_64-w64-mingw32-clang++.exe" 2^>nul') do (
    set "COMPILER=%%F"
    set "COMP_DIR=%%~dpF"
    set "WINDRES=!COMP_DIR!llvm-windres.exe"
    goto FOUND_COMPILER
)

for /f "delims=" %%F in ('dir /b /s "C:\Users\%USERNAME%\AppData\Local\Microsoft\WinGet\Packages\*g++.exe" 2^>nul') do (
    set "COMPILER=%%F"
    set "COMP_DIR=%%~dpF"
    set "WINDRES=!COMP_DIR!windres.exe"
    goto FOUND_COMPILER
)

echo ❌ x86_64 C++ compiler not found.
exit /b 1

:FOUND_COMPILER
echo ⚙️ Found C++ Compiler: %COMPILER%

REM Compile Resource File
if exist "%GUI_DIR%\resource.rc" (
    echo 📦 Compiling manifest and resources...
    "%WINDRES%" "%GUI_DIR%\resource.rc" -O coff -o "%GUI_DIR%\resource.o"
)

REM Build Main Executable
echo 🚀 Compiling CloudflareTunnelManagerGUI.exe...
"%COMPILER%" -O2 -std=c++17 -municode "%GUI_DIR%\src\main.cpp" "%GUI_DIR%\resource.o" -o "%GUI_DIR%\CloudflareTunnelManagerGUI.exe" -mwindows -lcomctl32 -ldwmapi -lole32 -luser32 -lgdi32 -ladvapi32

if %ERRORLEVEL% == 0 (
    echo.
    echo ✅ BUILD SUCCESSFUL!
    echo 📄 Executable created: %GUI_DIR%\CloudflareTunnelManagerGUI.exe
) else (
    echo.
    echo ❌ Compilation failed.
    exit /b 1
)

endlocal
