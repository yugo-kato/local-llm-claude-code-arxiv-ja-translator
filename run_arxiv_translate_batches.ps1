param(
    # Default: run this script from the project root, for example:
    # PS D:\arxiv_projects\yyyyMMddarXiv> .\run_arxiv_translate_batches.ps1 -SkipExistingJa
    [string]$ProjectRoot = (Get-Location).Path,

    # Leave empty to use: <ProjectRoot>\paper_info_md
    [string]$PaperDir = "",

    # Leave empty to use: <ProjectRoot>\.claude\agents\arxiv-abstract-ja-translate.md
    [string]$AgentFile = "",

    [string]$Model = "qwen/qwen3.6-27b",
    [Nullable[int]]$Start = $null,
    [Nullable[int]]$End = $null,
    [int]$BatchSize = 25,
    [switch]$SkipExistingJa,
    [switch]$DryRun,
    [string]$ClaudeExe = ""
)

$ErrorActionPreference = "Stop"

# Keep this PowerShell session UTF-8 friendly.
chcp 65001 | Out-Null
[Console]::InputEncoding  = [System.Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$OutputEncoding           = [System.Text.UTF8Encoding]::new($false)

# Normalize paths from the selected project root.
$ProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path

if ([string]::IsNullOrWhiteSpace($PaperDir)) {
    $PaperDir = Join-Path $ProjectRoot "paper_info_md"
}
if ([string]::IsNullOrWhiteSpace($AgentFile)) {
    $AgentFile = Join-Path $ProjectRoot ".claude\agents\arxiv-abstract-ja-translate.md"
}

if ([string]::IsNullOrWhiteSpace($ClaudeExe)) {
    $defaultClaude = Join-Path $env:USERPROFILE ".local\bin\claude.exe"
    if (Test-Path -LiteralPath $defaultClaude) {
        $ClaudeExe = $defaultClaude
    }
    else {
        $cmd = Get-Command claude -ErrorAction SilentlyContinue
        if ($null -ne $cmd) {
            $ClaudeExe = $cmd.Source
        }
        else {
            throw "claude.exe was not found. Set -ClaudeExe explicitly or add claude to PATH."
        }
    }
}

if (-not (Test-Path -LiteralPath $ProjectRoot -PathType Container)) { throw "ProjectRoot was not found: $ProjectRoot" }
if (-not (Test-Path -LiteralPath $PaperDir    -PathType Container)) { throw "PaperDir was not found: $PaperDir" }
if (-not (Test-Path -LiteralPath $AgentFile   -PathType Leaf))      { throw "Subagent file was not found: $AgentFile" }
if ($BatchSize -lt 1) { throw "BatchSize must be 1 or larger." }

$LogDir = Join-Path $ProjectRoot "logs"
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null

# Collect source markdown files only. Exclude already translated *_ja.md files and index files.
# Expected filename example: 001_2605.12345.md
$sourceFiles = Get-ChildItem -LiteralPath $PaperDir -File -Filter "*.md" |
    Where-Object {
        $_.Name -notmatch '_ja\.md$' -and
        $_.Name -notin @('_index.md') -and
        $_.Name -match '^(\d{3})_.*\.md$'
    } |
    ForEach-Object {
        $m = [regex]::Match($_.Name, '^(\d{3})_.*\.md$')
        [PSCustomObject]@{
            Prefix = [int]$m.Groups[1].Value
            Name   = $_.Name
            Path   = $_.FullName
        }
    } |
    Sort-Object Prefix, Name

if ($sourceFiles.Count -eq 0) {
    throw "No source markdown files matching NNN_*.md were found in: $PaperDir"
}

if ($null -eq $Start) { $Start = ($sourceFiles | Select-Object -First 1).Prefix }
if ($null -eq $End)   { $End   = ($sourceFiles | Select-Object -Last 1).Prefix }
if ($Start -gt $End)  { throw "Start must be less than or equal to End." }

Set-Location -LiteralPath $ProjectRoot

Write-Host "ProjectRoot : $ProjectRoot"
Write-Host "PaperDir    : $PaperDir"
Write-Host "AgentFile   : $AgentFile"
Write-Host "ClaudeExe   : $ClaudeExe"
Write-Host "Model       : $Model"
Write-Host "Range       : $(('{0:D3}' -f $Start))-$(('{0:D3}' -f $End))"
Write-Host "BatchSize   : $BatchSize"
Write-Host "LogDir      : $LogDir"
Write-Host ""

for ($batchStart = [int]$Start; $batchStart -le [int]$End; $batchStart += $BatchSize) {
    $batchEnd = [Math]::Min($batchStart + $BatchSize - 1, [int]$End)

    $start3 = "{0:D3}" -f $batchStart
    $end3   = "{0:D3}" -f $batchEnd

    $batchFiles = $sourceFiles | Where-Object { $_.Prefix -ge $batchStart -and $_.Prefix -le $batchEnd }

    if ($batchFiles.Count -eq 0) {
        Write-Host "Skipping empty batch $start3-$end3"
        continue
    }

    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $logFile = Join-Path $LogDir "claude_batch_${start3}_${end3}_${timestamp}.log"

    $fileListText = ($batchFiles | ForEach-Object { "- $($_.Path)" }) -join "`n"

    $skipInstruction = ""
    if ($SkipExistingJa) {
        $skipInstruction = @"

Additional skip rule:
- Before invoking the subagent for each input file, check whether the corresponding _ja.md file already exists.
- If the _ja.md file already exists, skip that input file and report it as skipped.
"@
    }

    $prompt = @"
Use the custom Claude Code subagent named arxiv-abstract-ja-translate.
The subagent definition is located at:
$AgentFile

Process the following Markdown files sequentially, one file at a time:
$fileListText

Important workflow:
- For each listed file, invoke the arxiv-abstract-ja-translate subagent once with exactly one full input file path.
- The subagent must create the corresponding _ja.md file according to its own instructions.
- Do not ask the subagent to process multiple files in one invocation.
- Do not process any file not listed above.
- Do not process *_ja.md files.
- Do not read or process _index.md, _index.json, or any JSON file.
- Do not modify files outside this directory:
  $PaperDir
- Do not modify the subagent definition file:
  $AgentFile
- If one file fails, record the failure and continue with the next file.
- Keep the final response compact.

For each file, report:
- numeric prefix
- input filename
- output filename
- success / skipped / failed

At the end, summarize:
- total listed files
- created files
- skipped files
- failed files
$skipInstruction
"@

    Write-Host "============================================================"
    Write-Host "Batch: $start3-$end3"
    Write-Host "Files: $($batchFiles.Count)"
    Write-Host "Log  : $logFile"
    Write-Host "============================================================"

    if ($DryRun) {
        Write-Host "[DryRun] Would run Claude for batch $start3-$end3"
        Write-Host $prompt
        Write-Host ""
        continue
    }

    try {
        & $ClaudeExe `
            -p $prompt `
            --model $Model `
            --permission-mode acceptEdits 2>&1 | Tee-Object -FilePath $logFile

        $exitCode = $LASTEXITCODE
        if ($exitCode -ne 0) {
            Write-Warning "Claude exited with code $exitCode for batch $start3-$end3. See log: $logFile"
        }
        else {
            Write-Host "Completed batch $start3-$end3"
        }
    }
    catch {
        Write-Warning "Error occurred in batch $start3-$end3"
        Write-Warning $_.Exception.Message
        Write-Warning "See log if it was created: $logFile"
    }

    Write-Host ""
}

Write-Host "All requested batches finished."
Write-Host "Logs are saved in: $LogDir"
