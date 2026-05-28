@echo off
setlocal EnableExtensions EnableDelayedExpansion

REM ============================================================
REM arXiv RSS -> Markdown project setup script
REM
REM This script:
REM   1. Creates dated output folders for cs.CV and astro-ph
REM   2. Copies project tool files into each output folder
REM   3. Copies .claude\agents into each output folder
REM   4. Generates .claude\settings.local.json for each output folder
REM   5. Downloads RSS XML and writes per-paper Markdown files
REM ============================================================

REM ============================================================
REM Get execution date as yyyyMMdd
REM ============================================================
for /f %%i in ('powershell.exe -NoProfile -Command "Get-Date -Format yyyyMMdd"') do set RUN_DATE=%%i

REM ============================================================
REM Source tools directory
REM ============================================================
set "SCRIPT_DIR=%~dp0"
set "TOOLS_DIR=%SCRIPT_DIR%."

REM When this setup batch lives under misc\, the repository root is one
REM directory up. Project-local copies still use their own directory.
if not exist "%TOOLS_DIR%\rss_to_arxiv_md.py" (
    if exist "%SCRIPT_DIR%..\rss_to_arxiv_md.py" (
        set "TOOLS_DIR=%SCRIPT_DIR%.."
    )
)

for %%I in ("%TOOLS_DIR%") do set "TOOLS_DIR=%%~fI"
set "TOOL_PY=%TOOLS_DIR%\rss_to_arxiv_md.py"
set "TOOL_PS1=%TOOLS_DIR%\run_arxiv_translate_batches.ps1"
set "TOOL_CLAUDE_DIR=%TOOLS_DIR%\.claude"

REM ============================================================
REM Output root directory
REM Optional first argument: output root, e.g. D:\arxiv_projects
REM Default: root of the drive where this script is located
REM ============================================================
if "%~1"=="" (
    set "OUTPUT_ROOT=%~d0"
) else (
    set "OUTPUT_ROOT=%~1"
)

REM ============================================================
REM Output project directories
REM ============================================================
set "CS_CV_DIR=%OUTPUT_ROOT%\%RUN_DATE%arXiv"
set "ASTRO_PH_DIR=%OUTPUT_ROOT%\%RUN_DATE%arXiv2"

set "CS_CV_OUT=%CS_CV_DIR%\paper_info_md"
set "ASTRO_PH_OUT=%ASTRO_PH_DIR%\paper_info_md"

set "CS_CV_RSS=%CS_CV_DIR%\cs.CV_rss.xml"
set "ASTRO_PH_RSS=%ASTRO_PH_DIR%\astro-ph_rss.xml"

REM ============================================================
REM Check source tool files
REM ============================================================
if not exist "%TOOLS_DIR%" (
    echo ERROR: Tools directory not found: "%TOOLS_DIR%"
    exit /b 1
)

if not exist "%TOOL_PY%" (
    echo ERROR: Python script not found: "%TOOL_PY%"
    exit /b 1
)

if not exist "%TOOL_PS1%" (
    echo ERROR: PowerShell translation script not found: "%TOOL_PS1%"
    exit /b 1
)

if not exist "%TOOL_CLAUDE_DIR%\agents\arxiv-abstract-ja-translate.md" (
    echo ERROR: Claude subagent file not found:
    echo "%TOOL_CLAUDE_DIR%\agents\arxiv-abstract-ja-translate.md"
    exit /b 1
)

REM ============================================================
REM Create and initialize project folders
REM ============================================================
call :InitProject "%CS_CV_DIR%"
if errorlevel 1 exit /b 1

call :InitProject "%ASTRO_PH_DIR%"
if errorlevel 1 exit /b 1

REM ============================================================
REM 1. cs.CV
REM Default target of rss_to_arxiv_md.py is cs.CV
REM ============================================================
echo.
echo ============================================================
echo Processing cs.CV
echo Project: %CS_CV_DIR%
echo Output : %CS_CV_OUT%
echo RSS    : %CS_CV_RSS%
echo ============================================================

call python "%CS_CV_DIR%\rss_to_arxiv_md.py" ^
  --output-dir "%CS_CV_OUT%" ^
  --save-rss "%CS_CV_RSS%"

if errorlevel 1 (
    echo.
    echo ERROR: cs.CV processing failed.
    exit /b 1
)

REM ============================================================
REM Wait 3 seconds for arXiv access interval
REM ============================================================
powershell.exe -NoProfile -Command "Start-Sleep -Seconds 3"

REM ============================================================
REM 2. astro-ph
REM ============================================================
echo.
echo ============================================================
echo Processing astro-ph
echo Project: %ASTRO_PH_DIR%
echo Output : %ASTRO_PH_OUT%
echo RSS    : %ASTRO_PH_RSS%
echo ============================================================

call python "%ASTRO_PH_DIR%\rss_to_arxiv_md.py" ^
  --astro-ph ^
  --output-dir "%ASTRO_PH_OUT%" ^
  --save-rss "%ASTRO_PH_RSS%"

if errorlevel 1 (
    echo.
    echo ERROR: astro-ph processing failed.
    exit /b 1
)

echo.
echo ============================================================
echo Done.
echo Date: %RUN_DATE%
echo cs.CV project   : %CS_CV_DIR%
echo astro-ph project: %ASTRO_PH_DIR%
echo ============================================================

endlocal
exit /b 0


REM ============================================================
REM Subroutine: Initialize one project folder
REM ============================================================
:InitProject
set "PROJECT_DIR=%~1"
set "PROJECT_PAPER_DIR=%PROJECT_DIR%\paper_info_md"
set "PROJECT_CLAUDE_DIR=%PROJECT_DIR%\.claude"

echo.
echo ------------------------------------------------------------
echo Initializing project: %PROJECT_DIR%
echo ------------------------------------------------------------

if not exist "%PROJECT_DIR%" mkdir "%PROJECT_DIR%"
if not exist "%PROJECT_PAPER_DIR%" mkdir "%PROJECT_PAPER_DIR%"
if not exist "%PROJECT_CLAUDE_DIR%" mkdir "%PROJECT_CLAUDE_DIR%"

REM Copy main tool files
copy /Y "%TOOL_PY%" "%PROJECT_DIR%\" > nul
if errorlevel 1 (
    echo ERROR: Failed to copy "%TOOL_PY%" to "%PROJECT_DIR%"
    exit /b 1
)

copy /Y "%TOOL_PS1%" "%PROJECT_DIR%\" > nul
if errorlevel 1 (
    echo ERROR: Failed to copy "%TOOL_PS1%" to "%PROJECT_DIR%"
    exit /b 1
)

REM Copy .claude directory tree.
REM settings.local.json is overwritten below with a project-specific version.
robocopy "%TOOL_CLAUDE_DIR%" "%PROJECT_CLAUDE_DIR%" /E /R:2 /W:1 /NFL /NDL /NJH /NJS /NP > nul
if %ERRORLEVEL% GEQ 8 (
    echo ERROR: robocopy failed while copying .claude to "%PROJECT_CLAUDE_DIR%"
    exit /b 1
)

REM Generate project-specific .claude\settings.local.json.
REM The allowed Get-ChildItem path must point to this project's paper_info_md\*_ja.md.
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^
  "$paperDir = '%PROJECT_PAPER_DIR%';" ^
  "$settingsPath = Join-Path '%PROJECT_CLAUDE_DIR%' 'settings.local.json';" ^
  "$allow = @(" ^
  "  'Bash(awk *)'," ^
  "  ('Bash(Get-ChildItem ""' + $paperDir + '\*_ja.md"")')," ^
  "  'Bash(Measure-Object)'," ^
  "  'Bash(Select-Object -ExpandProperty Count)'" ^
  ");" ^
  "$obj = [ordered]@{ permissions = [ordered]@{ allow = $allow } };" ^
  "$json = $obj | ConvertTo-Json -Depth 10;" ^
  "Set-Content -LiteralPath $settingsPath -Value $json -Encoding UTF8;"

if errorlevel 1 (
    echo ERROR: Failed to generate settings.local.json for "%PROJECT_DIR%"
    exit /b 1
)

echo Copied tools and generated settings:
echo   %PROJECT_CLAUDE_DIR%\settings.local.json

exit /b 0
