@echo off
title TurboEngine Mod Builder
echo =============================================
echo   TurboEngine Mod Builder for Sims 3
echo =============================================
echo.

set SIMS3_TOOLS=C:\MagiPacks\The Sims 3\Tools\Create a World Tool
set CSC=

:: Find csc.exe — try .NET Framework 3.5, then 4.0, then any available
if exist "C:\Windows\Microsoft.NET\Framework\v3.5\csc.exe" (
    set CSC=C:\Windows\Microsoft.NET\Framework\v3.5\csc.exe
    echo [OK] Found csc.exe (.NET 3.5^)
) else if exist "C:\Windows\Microsoft.NET\Framework\v4.0.30319\csc.exe" (
    set CSC=C:\Windows\Microsoft.NET\Framework\v4.0.30319\csc.exe
    echo [OK] Found csc.exe (.NET 4.0^)
) else (
    :: Search for any csc.exe
    for /f "delims=" %%i in ('where /r C:\Windows\Microsoft.NET csc.exe 2^>nul') do (
        set CSC=%%i
        goto :found_csc
    )
    echo [ERROR] csc.exe not found! Install .NET Framework SDK.
    pause
    exit /b 1
)
:found_csc
echo [OK] Using: %CSC%

:: Check references
if not exist "%SIMS3_TOOLS%\ScriptCore.dll" (
    echo [ERROR] ScriptCore.dll not found at:
    echo   %SIMS3_TOOLS%
    echo.
    echo   Edit this script and set SIMS3_TOOLS to your Create a World Tool path.
    pause
    exit /b 1
)
echo [OK] Found ScriptCore.dll
echo [OK] Found SimIFace.dll
echo.

:: Compile
echo [*] Compiling TurboEngine.cs...
"%CSC%" /target:library /out:TurboEngine.dll /optimize+ /nologo /reference:"%SIMS3_TOOLS%\ScriptCore.dll" /reference:"%SIMS3_TOOLS%\SimIFace.dll" TurboEngine.cs

if not exist TurboEngine.dll (
    echo [ERROR] Compilation failed! Check errors above.
    pause
    exit /b 1
)
echo [OK] TurboEngine.dll compiled
echo.

:: Package
echo [*] Building .package file...
python build_package.py

if exist TurboEngine.package (
    echo.
    echo =============================================
    echo   [SUCCESS] TurboEngine.package ready!
    echo =============================================
    echo.
    
    :: Auto-install option
    set MODS_DIR=%USERPROFILE%\Documents\Electronic Arts\The Sims 3\Mods\Packages
    if exist "%MODS_DIR%" (
        echo [?] Auto-install to Mods folder?
        echo     %MODS_DIR%
        echo.
        choice /M "Copy to Mods/Packages now"
        if errorlevel 2 goto :skip_install
        copy /Y TurboEngine.package "%MODS_DIR%\"
        echo [OK] Installed!
    ) else (
        echo [INFO] Copy TurboEngine.package to:
        echo   Documents\Electronic Arts\The Sims 3\Mods\Packages\
    )
    :skip_install
) else (
    echo [ERROR] Package build failed!
)

echo.
pause
