@echo off
title TurboEngine Mod Builder
cd /d "%~dp0"

echo =============================================
echo   TurboEngine Mod Builder for Sims 3
echo =============================================
echo.

:: =============================================================
::  CONFIGURATION
:: =============================================================
::  This mod needs the FULL game DLLs (ScriptCore.dll + SimIFace.dll).
::  The Create-a-World Tool ships stripped copies that are missing
::  RouteManager, AlarmHandle, World events, etc.
::
::  The script will auto-search common install locations.
::  If it cannot find them, set this path manually to the folder
::  that contains TS3.exe (or TS3W.exe) alongside the DLLs:
::
set SIMS3_GAME=C:\MagiPacks\The Sims 3
:: =============================================================

set CSC=
set REFS=

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

:: ─── FIND GAME DLLS ─────────────────────────────────────────
:: Try common locations where the FULL DLLs live.
:: The CAW Tool copies are stripped and will NOT work.

:: 1) Game\Bin under the configured root (standard EA layout)
if exist "%SIMS3_GAME%\Game\Bin\ScriptCore.dll" if exist "%SIMS3_GAME%\Game\Bin\SimIFace.dll" (
    set "REFS=%SIMS3_GAME%\Game\Bin"
    goto :found_refs
)

:: 2) Bin directly under the root (some repacks)
if exist "%SIMS3_GAME%\Bin\ScriptCore.dll" if exist "%SIMS3_GAME%\Bin\SimIFace.dll" (
    set "REFS=%SIMS3_GAME%\Bin"
    goto :found_refs
)

:: 3) Root itself (some portable/repack layouts)
if exist "%SIMS3_GAME%\ScriptCore.dll" if exist "%SIMS3_GAME%\SimIFace.dll" (
    set "REFS=%SIMS3_GAME%"
    goto :found_refs
)

:: 4) Gameplay subfolder (some repacks)
if exist "%SIMS3_GAME%\Gameplay\ScriptCore.dll" if exist "%SIMS3_GAME%\Gameplay\SimIFace.dll" (
    set "REFS=%SIMS3_GAME%\Gameplay"
    goto :found_refs
)

:: 5) Standard Program Files locations
for %%P in (
    "C:\Program Files\Electronic Arts\The Sims 3\Game\Bin"
    "C:\Program Files (x86)\Electronic Arts\The Sims 3\Game\Bin"
) do (
    if exist "%%~P\ScriptCore.dll" if exist "%%~P\SimIFace.dll" (
        set "REFS=%%~P"
        goto :found_refs
    )
)

:: Nothing found — tell the user exactly what to do
echo [ERROR] Could not find the FULL game DLLs (ScriptCore.dll + SimIFace.dll).
echo.
echo   Searched under: %SIMS3_GAME%
echo     - Game\Bin\
echo     - Bin\
echo     - Gameplay\
echo     - (root)
echo.
echo   IMPORTANT: The Create-a-World Tool copies will NOT work.
echo   They are stripped and missing RouteManager, AlarmHandle, etc.
echo.
echo   HOW TO FIX:
echo     1. Find your Sims 3 game folder (it has TS3.exe or TS3W.exe)
echo     2. Open this script in Notepad
echo     3. Change the SIMS3_GAME line near the top to point there
echo        Example: set SIMS3_GAME=C:\Games\The Sims 3
echo.
echo   HINT: Search your PC for ScriptCore.dll — pick the LARGEST
echo   copy (usually 10+ MB). The CAW Tool copy is only ~1-2 MB.
goto :fail

:found_refs
echo [OK] Found ScriptCore.dll in: %REFS%
echo [OK] Found SimIFace.dll  in: %REFS%
echo.

:: ─── COMPILE ────────────────────────────────────────────────
:: Delete stale DLL so the existence check after compile is accurate
if exist TurboEngine.dll del TurboEngine.dll

echo [*] Compiling TurboEngine.cs...
"%CSC%" /target:library /out:TurboEngine.dll /optimize+ /nologo ^
    /reference:"%REFS%\ScriptCore.dll" ^
    /reference:"%REFS%\SimIFace.dll" ^
    TurboEngine.cs

if not exist TurboEngine.dll (
    echo.
    echo [ERROR] Compilation failed! Check the errors above.
    echo.
    echo   If you see "does not contain a definition" errors, your DLLs
    echo   are probably the stripped CAW Tool versions.
    echo   You need the FULL DLLs from the game's own Bin folder.
    echo   See the SIMS3_GAME setting at the top of this script.
    goto :fail
)
echo [OK] TurboEngine.dll compiled
echo.

:: ─── PACKAGE ────────────────────────────────────────────────
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
