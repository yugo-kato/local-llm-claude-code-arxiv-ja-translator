# arXiv Listing Parser and Abstract Translator

This repository contains small PowerShell utilities for converting a saved arXiv listing page into per-paper Markdown files, then optionally generating Japanese translations of each abstract with Claude Code.

To process many Markdown files within the limited context length of a local LLM, this workflow invokes Claude Code in non-interactive execution mode with `claude -p` and further delegates each file-level task to a subagent. This avoids packing the contents of all files into a single conversation context and instead processes each file as an independent, smaller task.

## Contents

- `parse_arxiv_html.ps1` parses a saved arXiv listing HTML file and writes one Markdown metadata file per paper.
- `run_arxiv_translate_batches.ps1` runs Claude Code in batches to create `_ja.md` files that preserve the original metadata and abstract while adding a Japanese abstract translation.
- `.claude/agents/arxiv-abstract-ja-translate.md` defines the Claude Code subagent used for one-file-at-a-time abstract translation.

## Prerequisites

- PowerShell 7 or Windows PowerShell
- A saved arXiv listing HTML page, for example:
  - `Computer Vision and Pattern Recognition.html`
- Claude Code CLI, only if you want to run the translation batch script
- LM Studio running a local LLM with the `qwen/qwen3.6-27b` model

For LM Studio setup with Claude Code, see the official LM Studio integration guide:
<https://lmstudio.ai/docs/integrations/claude-code>

The saved HTML page and its browser-generated asset folder are intentionally not included in this repository.

## Save the arXiv Listing Page

Open the arXiv new submissions page for Computer Vision and Pattern Recognition:

<https://arxiv.org/list/cs.CV/new>

Save the page as complete HTML from your browser. For example, this may create:

```text
Computer Vision and Pattern Recognition.html
Computer Vision and Pattern Recognition_files/
```

Use the saved `.html` file as the input for the parser.

## Parse the arXiv HTML Listing

Run the parser from the repository root:

```powershell
.\parse_arxiv_html.ps1 `
  -InputHtml "Computer Vision and Pattern Recognition.html" `
  -OutputDir "paper_info_md"
```

The script creates `paper_info_md/` and writes files named like:

```text
001_2605.12345.md
002_2605.12346.md
...
```

Each generated file includes metadata such as title, authors, arXiv links, subjects, comments, and the original abstract.

## Generate Japanese Abstract Translations

After parsing the HTML listing, run the batch translation script:

```powershell
.\run_arxiv_translate_batches.ps1 `
  -ProjectRoot (Get-Location).Path `
  -BatchSize 25 `
  -SkipExistingJa
```

By default, the batch script is intended to run through Claude Code CLI using a local LLM served by LM Studio with the model name `qwen/qwen3.6-27b`.

If you use a different runtime environment, model provider, or model name, update `run_arxiv_translate_batches.ps1` accordingly before running the translation workflow.

Configure `.claude\settings.local.json` with appropriate permissions for your local folder paths. For example:

```json
{
  "permissions": {
    "allow": [
      "Bash(awk *)",
      "Bash(Get-ChildItem \"H:\\\\20260525arXiv\\\\paper_info_md\\\\*_ja.md\")",
      "Bash(Measure-Object)",
      "Bash(Select-Object -ExpandProperty Count)"
    ]
  }
}
```

Replace the example folder path with the path used on your machine.

Useful options:

- `-Start` and `-End` limit processing to numeric filename prefixes, such as `-Start 1 -End 50`.
- `-BatchSize` controls how many source Markdown files are included in each Claude Code prompt.
- `-SkipExistingJa` avoids overwriting existing translated files.
- `-DryRun` prints the planned prompt without invoking Claude Code.
- `-ClaudeExe` can be used when `claude.exe` is not available on `PATH`.

The translated files are written next to the originals with `_ja` before the extension:

```text
001_2605.12345.md
001_2605.12345_ja.md
```

## Output Format

The translation subagent preserves the source file and adds a Japanese section immediately after the original abstract:

```markdown
## Abstract

Original English abstract...

## Abstract（日本語訳）

Japanese translation...
```

## Notes

- The parser is designed for saved arXiv listing pages and may need adjustment if arXiv changes its HTML structure.
- Generated output directories such as `paper_info_md/` and `logs/` are usually best kept out of version control.
