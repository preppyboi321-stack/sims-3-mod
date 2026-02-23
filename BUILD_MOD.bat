@echo off
title TurboEngine Mod Builder
cd /d "%~dp0"

echo =============================================
echo   TurboEngine Mod Builder for Sims 3
echo =============================================
echo.

:: =============================================================
::  CONFIGURATION — edit these two paths if the defaults are wrong
:: =============================================================
:: Folder that contains BOTH ScriptCore.dll and SimIFace.dll.
:: The Create a World Tool ships both files.
set SIMS3_REFS=C:\MagiPacks\The Sims 3\Tools\Create a World Tool
:: =============================================================

set CSC=

:: ─── FIND COMPILER ──────────────────────────────────────────
if exist "C:\Windows\Microsoft.NET\Framework\v3.5\csc.exe" (
    set "CSC=C:\Windows\Microsoft.NET\Framework\v3.5\csc.exe"
    echo [OK] Found csc.exe ^(.NET 3.5^)
) else if exist "C:\Windows\Microsoft.NET\Framework\v4.0.30319\csc.exe" (
    set "CSC=C:\Windows\Microsoft.NET\Framework\v4.0.30319\csc.exe"
    echo [OK] Found csc.exe ^(.NET 4.0^)
) else (
    for /f "delims=" %%i in ('where /r C:\Windows\Microsoft.NET csc.exe 2^>nul') do (
        set "CSC=%%i"
        goto :found_csc
    )
    echo [ERROR] csc.exe not found!
    echo.
    echo   Install the .NET Framework 3.5 or 4.0 SDK and try again.
    goto :fail
)
:found_csc
echo [OK] Using: %CSC%

:: ─── CHECK SOURCE FILE ──────────────────────────────────────
if not exist "TurboEngine.cs" (
    echo [ERROR] TurboEngine.cs not found in:
    echo   %CD%
    echo.
    echo   Make sure this script is in the same folder as TurboEngine.cs.
    goto :fail
)
echo [OK] Found TurboEngine.cs

:: ─── CHECK REFERENCES ───────────────────────────────────────
if not exist "%SIMS3_REFS%\ScriptCore.dll" (
    echo [ERROR] ScriptCore.dll not found at:
    echo   %SIMS3_REFS%\ScriptCore.dll
    echo.
    echo   FIX: Open this script in Notepad and change the SIMS3_REFS
    echo        path at the top to the folder containing your DLLs.
    goto :fail
)
echo [OK] Found ScriptCore.dll

if not exist "%SIMS3_REFS%\SimIFace.dll" (
    echo [ERROR] SimIFace.dll not found at:
    echo   %SIMS3_REFS%\SimIFace.dll
    echo.
    echo   FIX: Open this script in Notepad and change the SIMS3_REFS
    echo        path at the top to the folder containing your DLLs.
    goto :fail
)
echo [OK] Found SimIFace.dll
echo.

:: ─── COMPILE ────────────────────────────────────────────────
:: Delete stale DLL so the existence check after compile is accurate
if exist TurboEngine.dll del TurboEngine.dll

echo [*] Compiling TurboEngine.cs...
"%CSC%" /target:library /out:TurboEngine.dll /optimize+ /nologo ^
    /reference:"%SIMS3_REFS%\ScriptCore.dll" ^
    /reference:"%SIMS3_REFS%\SimIFace.dll" ^
    TurboEngine.cs

if not exist TurboEngine.dll (
    echo.
    echo [ERROR] Compilation failed! Check the errors above.
    goto :fail
)
echo [OK] TurboEngine.dll compiled
echo.

:: ─── PACKAGE ────────────────────────────────────────────────
:: Check for Python before attempting the package step
where python >nul 2>&1
if errorlevel 1 (
    echo [WARN] Python not found in PATH — skipping .package build.
    echo   Install Python 3 and add it to PATH, then re-run this script.
    echo.
    echo   Your compiled DLL is ready at:
    echo   %CD%\TurboEngine.dll
    goto :done
)

if not exist "build_package.py" (
    echo [WARN] build_package.py not found — skipping .package build.
    echo.
    echo   Your compiled DLL is ready at:
    echo   %CD%\TurboEngine.dll
    goto :done
)

echo [*] Building .package file...
python build_package.py

if not exist TurboEngine.package (
    echo.
    echo [ERROR] Package build failed!
    goto :fail
)

echo.
echo =============================================
echo   [SUCCESS] TurboEngine.package ready!
echo =============================================
echo.

:: ─── AUTO-INSTALL ───────────────────────────────────────────
set MODS_DIR=%USERPROFILE%\Documents\Electronic Arts\The Sims 3\Mods\Packages
if exist "%MODS_DIR%" (
    echo [?] Auto-install to Mods folder?
    echo     %MODS_DIR%
    echo.
    choice /M "Copy to Mods/Packages now"
    if errorlevel 2 goto :done
    copy /Y TurboEngine.package "%MODS_DIR%\" >nul
    echo [OK] Installed!
) else (
    echo [INFO] Copy TurboEngine.package to:
    echo   Documents\Electronic Arts\The Sims 3\Mods\Packages\
)

:done
echo.
pause
exit /b 0

:fail
echo.
pause
exit /b 1
