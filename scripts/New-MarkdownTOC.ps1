function New-MarkdownTOC {
    <#
    .SYNOPSIS
        Generates or updates a Markdown table of contents.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$Path,
        [ValidateRange(1, 6)][int]$MinLevel = 2,
        [ValidateRange(1, 6)][int]$MaxLevel = 6,
        [switch]$AutoUpdate,
        [switch]$Preview,
        [switch]$DryRun
    )

    $ErrorActionPreference = 'Stop'
    $fullPath = [System.IO.Path]::GetFullPath($Path)
    if (-not [System.IO.File]::Exists($fullPath)) { throw "Markdown file not found: $fullPath" }
    if ($MinLevel -gt $MaxLevel) { throw 'MinLevel cannot be greater than MaxLevel.' }

    $content = [System.IO.File]::ReadAllText($fullPath)
    $tocLines = [System.Collections.Generic.List[string]]::new()
    $slugCounts = [System.Collections.Generic.Dictionary[string, int]]::new([System.StringComparer]::Ordinal)
    $inFence = $false

    foreach ($line in ($content -split '\r?\n')) {
        if ($line -match '^\s*(```|~~~)') { $inFence = -not $inFence; continue }
        if ($inFence -or $line -notmatch '^(#{1,6})\s+(.+?)\s*$') { continue }

        $level = $Matches[1].Length
        $heading = $Matches[2] -replace '\s+#+\s*$', ''
        if ($level -lt $MinLevel -or $level -gt $MaxLevel -or $heading -ieq 'Table of Contents') { continue }

        $plainHeading = $heading -replace '<[^>]+>', '' -replace '[`*_~]', ''
        $plainHeading = $plainHeading.Trim()
        if ([string]::IsNullOrWhiteSpace($plainHeading)) { continue }

        $slug = $plainHeading.ToLowerInvariant()
        $slug = $slug -replace '[^\p{L}\p{Nd}\s-]', '' -replace '\s+', '-'
        $slug = $slug.Trim('-')
        if ($slugCounts.ContainsKey($slug)) {
            $slugCounts[$slug]++
            $slug = "$slug-$($slugCounts[$slug])"
        } else {
            $slugCounts[$slug] = 0
        }
        $indent = '  ' * ($level - $MinLevel)
        $tocLines.Add("$indent- [$plainHeading](#$slug)")
    }

    $toc = $tocLines -join "`n"
    if ($Preview -or -not $AutoUpdate) { return $toc }

    $detailsPattern = '(?ms)(<details>\r?\n<summary><strong>[^<]*Table of Contents</strong></summary>)(.*?)(\r?\n</details>)'
    if (-not [regex]::IsMatch($content, $detailsPattern)) {
        throw "A collapsible Table of Contents block was not found in '$fullPath'."
    }
    $updated = [regex]::Replace($content, $detailsPattern, ('$1' + "`n`n$toc`n" + '$3'), 1)
    if ($updated -eq $content) {
        Write-Output 'README table of contents is current.'
        return
    }
    if ($DryRun) {
        Write-Output 'Would update README table of contents.'
    } elseif ($PSCmdlet.ShouldProcess($fullPath, 'Update Markdown table of contents')) {
        [System.IO.File]::WriteAllText($fullPath, $updated, [System.Text.UTF8Encoding]::new($false))
        Write-Output 'Updated README table of contents.'
    }
}
