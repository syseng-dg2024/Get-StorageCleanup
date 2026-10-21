@echo off
cd /d "%~dp0"

REM Elevate if not admin
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Elevating to Administrator...
    powershell -NoProfile -Command "Start-Process cmd -ArgumentList '/c \"\"%~f0\"\"' -Verb RunAs"
    exit /b %ERRORLEVEL%
)

set "BASE=%~dp0"
set "MODPSD1=%BASE%Get-StorageCleanup\Get-StorageCleanup.psd1"
set "URL=https://github.com/syseng-dg2024/Get-StorageCleanup/archive/refs/heads/main.zip"

REM Download if the module folder is missing
if not exist "%MODPSD1%" (
    echo Get-StorageCleanup not found. Downloading latest from GitHub...
    powershell -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; $b='%BASE%'; $z=Join-Path $b 'gsc.zip'; $t=Join-Path $b 'gsc_tmp'; Invoke-WebRequest -UseBasicParsing -Uri '%URL%' -OutFile $z; Expand-Archive $z -DestinationPath $t -Force; $p=(Get-ChildItem $t -Recurse -Filter Get-StorageCleanup.psd1 | Select-Object -First 1).Directory.FullName; Move-Item $p (Join-Path $b 'Get-StorageCleanup'); Remove-Item $z,$t -Recurse -Force"
    if not exist "%MODPSD1%" (
        echo ERROR: Download or extract failed. Check internet access to github.com.
        pause
        exit /b 1
    )
)

REM Run in place
powershell.exe -ExecutionPolicy Bypass -NoProfile -Command "Import-Module -Force '%MODPSD1%'; Get-StorageCleanup"
exit /b %ERRORLEVEL%