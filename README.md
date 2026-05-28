# arXiv RSS Markdown Exporter and Abstract Translator

This repository contains small utilities for downloading arXiv RSS feeds, converting each RSS item into a per-paper Markdown file, and optionally generating Japanese translations of abstracts with Claude Code.

The v0.2 workflow no longer uses saved arXiv HTML pages. It downloads RSS directly from `https://rss.arxiv.org/rss/`.

To process many Markdown files within the limited context length of a local LLM, the translation workflow invokes Claude Code in non-interactive execution mode with `claude -p` and delegates each file-level task to a subagent. This keeps each paper translation as an independent, smaller task.

## Contents

- `rss_to_arxiv_md.py` downloads an arXiv RSS feed or reads a saved RSS XML file and writes one Markdown metadata file per paper.
- `misc/run_arxiv_rss_md_with_project_setup.bat` creates dated project folders for `cs.CV` and `astro-ph`, copies the required tools and `.claude` files, downloads RSS, and writes Markdown files.
- `run_arxiv_translate_batches.ps1` runs Claude Code in batches to create `_ja.md` files that preserve the original metadata and abstract while adding a Japanese abstract translation.
- `.claude/agents/arxiv-abstract-ja-translate.md` defines the Claude Code subagent used for one-file-at-a-time abstract translation.

## Prerequisites

- Windows PowerShell or PowerShell 7
- Python 3
- Internet access to `rss.arxiv.org` for live RSS download
- Claude Code CLI, only if you want to run the translation batch script
- LM Studio running a local LLM with the `qwen/qwen3.6-27b` model, if you use the default translation settings

For LM Studio setup with Claude Code, see the official LM Studio integration guide:
<https://lmstudio.ai/docs/integrations/claude-code>

## Generate Markdown From arXiv RSS

### Recommended: project setup batch

Run the setup batch from this repository:

```bat
misc\run_arxiv_rss_md_with_project_setup.bat
```

The batch file resolves the repository root as the source tool directory when it is run from `misc\`. It copies `rss_to_arxiv_md.py`, `run_arxiv_translate_batches.ps1`, and `.claude` files into each dated project folder.

It creates dated project folders under the root of the current drive by default:

```text
<drive>:\yyyyMMddarXiv
<drive>:\yyyyMMddarXiv2
```

By default:

- `<drive>:\yyyyMMddarXiv` receives `cs.CV` RSS output.
- `<drive>:\yyyyMMddarXiv2` receives `astro-ph` RSS output.
- Markdown files are written under each project's `paper_info_md\` directory.
- The downloaded RSS XML is saved as `cs.CV_rss.xml` or `astro-ph_rss.xml`.

To write project folders under a specific output root, pass it as the first argument:

```bat
misc\run_arxiv_rss_md_with_project_setup.bat D:\arxiv_projects
```

### Direct Python usage

Default `cs.CV` RSS:

```powershell
python .\rss_to_arxiv_md.py `
  --output-dir .\paper_info_md `
  --save-rss .\cs.CV_rss.xml
```

`astro-ph` RSS:

```powershell
python .\rss_to_arxiv_md.py `
  --astro-ph `
  --output-dir .\paper_info_md `
  --save-rss .\astro-ph_rss.xml
```

Use another arXiv category:

```powershell
python .\rss_to_arxiv_md.py `
  --category cs.LG `
  --output-dir .\paper_info_md `
  --save-rss .\cs.LG_rss.xml
```

Offline or repeatable run from an already saved RSS XML file:

```powershell
python .\rss_to_arxiv_md.py `
  --rss-file .\cs.CV_rss.xml `
  --output-dir .\paper_info_md
```

Useful options:

- `--only-new` exports only RSS items whose announce type is `new`.
- `--clear-output-dir` deletes existing `*.md` files in the output directory before writing new files.
- `--rss-url` uses an explicit RSS URL instead of `--category`.
- `--save-rss` saves the downloaded RSS XML for inspection or later offline use.

The script creates files named like:

```text
001_2605.12345.md
002_2605.12346.md
...
```

Each generated file includes metadata such as title, authors, arXiv links, subjects, RSS section, listing date, and the original abstract.

## Generate Japanese Abstract Translations

After generating Markdown files, run the batch translation script from the project folder that contains `paper_info_md\`:

```powershell
.\run_arxiv_translate_batches.ps1 `
  -ProjectRoot (Get-Location).Path `
  -BatchSize 25 `
  -SkipExistingJa
```

By default, the batch script is intended to run through Claude Code CLI using a local LLM served by LM Studio with the model name `qwen/qwen3.6-27b`.

If you use a different runtime environment, model provider, or model name, update the `-Model` argument or the script settings before running the translation workflow.

The setup batch generates `.claude\settings.local.json` for each dated project folder. If you run the tools manually, configure `.claude\settings.local.json` with appropriate permissions for your local folder paths. For example:

```json
{
  "permissions": {
    "allow": [
      "Bash(awk *)",
      "Bash(Get-ChildItem \"D:\\\\arxiv_projects\\\\yyyyMMddarXiv\\\\paper_info_md\\\\*_ja.md\")",
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
- `-Model` sets the Claude Code model name.

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

- This v0.2 workflow uses RSS, not saved HTML listing pages.
- RSS exports all feed items by default, including `new`, `cross`, `replace`, and `replace-cross` announce types.
- Generated output directories such as `paper_info_md\` and `logs\` are usually best kept out of version control.
