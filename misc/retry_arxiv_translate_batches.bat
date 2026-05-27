@echo off
setlocal enabledelayedexpansion

set MAX_RETRY=5

REM Usage:
REM   retry_arxiv_translate_batches.bat [yyyyMMdd] [output_root]
REM Examples:
REM   retry_arxiv_translate_batches.bat
REM   retry_arxiv_translate_batches.bat yyyyMMdd D:\arxiv_projects

if "%~1"=="" (
    for /f %%i in ('powershell.exe -NoProfile -Command "Get-Date -Format yyyyMMdd"') do set RUN_DATE=%%i
) else (
    set "RUN_DATE=%~1"
)

if "%~2"=="" (
    set "OUTPUT_ROOT=%~d0"
) else (
    set "OUTPUT_ROOT=%~2"
)

call :ProcessProject "%OUTPUT_ROOT%\%RUN_DATE%arXiv"
if errorlevel 1 exit /b 1

call :ProcessProject "%OUTPUT_ROOT%\%RUN_DATE%arXiv2"
if errorlevel 1 exit /b 1

echo [OK] All tasks finished.
exit /b 0


:ProcessProject
set "PROJECT=%~1"
set "PAPER_DIR=%PROJECT%\paper_info_md"

echo ============================================================
echo Project: %PROJECT%
echo ============================================================

if not exist "%PROJECT%\run_arxiv_translate_batches.ps1" (
    echo [ERROR] Script not found: %PROJECT%\run_arxiv_translate_batches.ps1
    exit /b 1
)

if not exist "%PAPER_DIR%" (
    echo [ERROR] Paper directory not found: %PAPER_DIR%
    exit /b 1
)

set RETRY=0

:LOOP
set /a RETRY+=1

for /f %%A in ('powershell.exe -NoProfile -Command "(Get-ChildItem -Path '%PAPER_DIR%' -Filter '*.md' -File | Where-Object { $_.Name -notlike '*_ja.md' } | Measure-Object).Count"') do set SRC_COUNT=%%A

for /f %%A in ('powershell.exe -NoProfile -Command "(Get-ChildItem -Path '%PAPER_DIR%' -Filter '*_ja.md' -File | Measure-Object).Count"') do set JA_COUNT=%%A

echo [CHECK] %PROJECT%
echo [CHECK] source md: !SRC_COUNT!
echo [CHECK] ja md    : !JA_COUNT!
echo [CHECK] retry    : !RETRY! / %MAX_RETRY%

if "!SRC_COUNT!"=="!JA_COUNT!" (
    echo [OK] Already complete: %PROJECT%
    exit /b 0
)

if !RETRY! GTR %MAX_RETRY% (
    echo [ERROR] Max retry exceeded: %PROJECT%
    echo [ERROR] source md: !SRC_COUNT!, ja md: !JA_COUNT!
    exit /b 1
)

cd /d "%PROJECT%"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\run_arxiv_translate_batches.ps1" -SkipExistingJa

if errorlevel 1 (
    echo [ERROR] Translation failed in %PROJECT%
    exit /b 1
)

goto LOOP
