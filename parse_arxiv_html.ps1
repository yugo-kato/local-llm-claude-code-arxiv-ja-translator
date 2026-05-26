param(
    [string]$InputHtml = "Computer Vision and Pattern Recognition.html",
    [string]$OutputDir = "paper_info_md"
)

$ErrorActionPreference = "Stop"

function Convert-HtmlText {
    param([string]$HtmlFragment)

    if ([string]::IsNullOrWhiteSpace($HtmlFragment)) {
        return ""
    }

    $text = $HtmlFragment
    $text = $text -replace "(?is)<script\b.*?</script>", " "
    $text = $text -replace "(?is)<style\b.*?</style>", " "
    $text = $text -replace "(?is)<span\s+class=""descriptor"">.*?</span>", " "
    $text = $text -replace "(?is)<br\s*/?>", " "
    $text = $text -replace "(?is)</p>|</div>|</li>", " "
    $text = $text -replace "(?is)<[^>]+>", " "
    $text = [System.Net.WebUtility]::HtmlDecode($text)
    $text = $text -replace [char]0x00A0, " "
    $text = $text -replace "\s+", " "
    $text = $text -replace "\s+([,.;:!?])", '$1'
    $text = $text -replace "([(\[])\s+", '$1'
    $text = $text -replace "\s+([)\]])", '$1'

    return $text.Trim()
}

function Get-GroupValue {
    param(
        [string]$Text,
        [string]$Pattern
    )

    $match = [regex]::Match($Text, $Pattern, [System.Text.RegularExpressions.RegexOptions]::Singleline -bor [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if ($match.Success) {
        return $match.Groups["value"].Value
    }

    return ""
}

function Get-FieldText {
    param(
        [string]$MetaHtml,
        [string]$ClassName
    )

    $pattern = "(?is)<div\s+class=""$([regex]::Escape($ClassName))[^""]*"">(?<value>.*?)</div>"
    $value = Get-GroupValue -Text $MetaHtml -Pattern $pattern
    return Convert-HtmlText $value
}

function Get-PrimarySubject {
    param([string]$MetaHtml)

    $value = Get-GroupValue -Text $MetaHtml -Pattern '(?is)<span\s+class="primary-subject">(?<value>.*?)</span>'
    return Convert-HtmlText $value
}

function Format-MarkdownLine {
    param(
        [string]$Name,
        [string]$Value
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $null
    }

    return "- **${Name}:** $Value"
}

function Add-OptionalLine {
    param(
        [System.Collections.Generic.List[string]]$Lines,
        [AllowNull()][string]$Line
    )

    if (-not [string]::IsNullOrWhiteSpace($Line)) {
        $Lines.Add($Line)
    }
}

if (-not [System.IO.Path]::IsPathRooted($InputHtml)) {
    $InputHtml = Join-Path $PSScriptRoot $InputHtml
}

if (-not [System.IO.Path]::IsPathRooted($OutputDir)) {
    $OutputDir = Join-Path $PSScriptRoot $OutputDir
}

if (-not (Test-Path -LiteralPath $InputHtml -PathType Leaf)) {
    throw "Input HTML not found: $InputHtml"
}

$html = Get-Content -LiteralPath $InputHtml -Raw -Encoding UTF8
$listingDate = Convert-HtmlText (Get-GroupValue -Text $html -Pattern '(?is)<h3>\s*Showing new listings for (?<value>.*?)</h3>')

$headingPattern = [regex]::new('(?is)<h3>(?<value>(?:New submissions|Cross submissions|Replacement submissions).*?)</h3>')
$headings = foreach ($headingMatch in $headingPattern.Matches($html)) {
    [pscustomobject]@{
        Index = $headingMatch.Index
        Text = (Convert-HtmlText $headingMatch.Groups["value"].Value) -replace "\s*\(showing.*$", ""
    }
}

$entryPattern = [regex]::new('(?is)<dt>\s*<a\s+name="item(?<number>\d+)">\[\d+\]</a>(?<dt>.*?)</dt>\s*<dd>\s*<div\s+class="meta">(?<meta>.*?)</div>\s*</dd>')
$entryMatches = $entryPattern.Matches($html)

if ($entryMatches.Count -eq 0) {
    throw "No arXiv entries were found in: $InputHtml"
}

New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null

$written = 0
foreach ($entryMatch in $entryMatches) {
    $number = [int]$entryMatch.Groups["number"].Value
    $dtHtml = $entryMatch.Groups["dt"].Value
    $metaHtml = $entryMatch.Groups["meta"].Value

    $section = ($headings | Where-Object { $_.Index -lt $entryMatch.Index } | Select-Object -Last 1).Text
    $arxivId = Convert-HtmlText (Get-GroupValue -Text $dtHtml -Pattern '(?is)<a\s+href="https://arxiv\.org/abs/[^"]+"\s+title="Abstract"\s+id="[^"]+">\s*arXiv:(?<value>.*?)\s*</a>')
    $abstractUrl = Get-GroupValue -Text $dtHtml -Pattern '(?is)<a\s+href="(?<value>https://arxiv\.org/abs/[^"]+)"\s+title="Abstract"'
    $pdfUrl = Get-GroupValue -Text $dtHtml -Pattern '(?is)<a\s+href="(?<value>https://arxiv\.org/pdf/[^"]+)"'
    $htmlUrl = Get-GroupValue -Text $dtHtml -Pattern '(?is)<a\s+href="(?<value>https://arxiv\.org/html/[^"]+)"'
    $formatUrl = Get-GroupValue -Text $dtHtml -Pattern '(?is)<a\s+href="(?<value>https://arxiv\.org/format/[^"]+)"'

    $title = Get-FieldText -MetaHtml $metaHtml -ClassName "list-title"
    $authors = Get-FieldText -MetaHtml $metaHtml -ClassName "list-authors"
    $comments = Get-FieldText -MetaHtml $metaHtml -ClassName "list-comments"
    $subjects = Get-FieldText -MetaHtml $metaHtml -ClassName "list-subjects"
    $primarySubject = Get-PrimarySubject $metaHtml
    $abstract = Convert-HtmlText (Get-GroupValue -Text $metaHtml -Pattern '(?is)<p\s+class="mathjax">\s*(?<value>.*?)\s*</p>')

    if ([string]::IsNullOrWhiteSpace($arxivId)) {
        $arxivId = "unknown"
    }

    if ([string]::IsNullOrWhiteSpace($title)) {
        $title = "Untitled"
    }

    $fileBase = "{0:D3}_{1}.md" -f $number, ($arxivId -replace "[^\w.-]", "_")
    $filePath = Join-Path $OutputDir $fileBase

    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add("# [$number] $title")
    $lines.Add("")
    Add-OptionalLine -Lines $lines -Line (Format-MarkdownLine -Name "Number" -Value $number)
    Add-OptionalLine -Lines $lines -Line (Format-MarkdownLine -Name "Section" -Value $section)
    Add-OptionalLine -Lines $lines -Line (Format-MarkdownLine -Name "Listing date" -Value $listingDate)
    if ($abstractUrl) {
        $lines.Add("- **arXiv:** [$arxivId]($abstractUrl)")
    } else {
        Add-OptionalLine -Lines $lines -Line (Format-MarkdownLine -Name "arXiv" -Value $arxivId)
    }
    Add-OptionalLine -Lines $lines -Line (Format-MarkdownLine -Name "Authors" -Value $authors)
    Add-OptionalLine -Lines $lines -Line (Format-MarkdownLine -Name "Comments" -Value $comments)
    Add-OptionalLine -Lines $lines -Line (Format-MarkdownLine -Name "Primary subject" -Value $primarySubject)
    Add-OptionalLine -Lines $lines -Line (Format-MarkdownLine -Name "Subjects" -Value $subjects)
    Add-OptionalLine -Lines $lines -Line (Format-MarkdownLine -Name "PDF" -Value $pdfUrl)
    Add-OptionalLine -Lines $lines -Line (Format-MarkdownLine -Name "HTML" -Value $htmlUrl)
    Add-OptionalLine -Lines $lines -Line (Format-MarkdownLine -Name "Other formats" -Value $formatUrl)
    $lines.Add("")
    $lines.Add("## Abstract")
    $lines.Add("")
    $lines.Add($abstract)

    Set-Content -LiteralPath $filePath -Value ($lines -join [Environment]::NewLine) -Encoding utf8NoBOM
    $written++
}

Write-Output "Input: $InputHtml"
Write-Output "Output: $OutputDir"
Write-Output "Entries found: $($entryMatches.Count)"
Write-Output "Markdown files written: $written"
