function Test-ReadmeStructure {
    <#
    .SYNOPSIS
        Validates README headings against the repository glmeta contract.
    .DESCRIPTION
        Parses Markdown ATX headings outside fenced code blocks, normalizes
        presentation markup, and reports every configured required heading.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [Parameter(Mandatory)][string]$ConfigPath,
        [switch]$Quiet
    )

    $readmePath = [System.IO.Path]::Combine([System.IO.Path]::GetFullPath($RepositoryRoot), 'README.md')
    if (-not [System.IO.File]::Exists($readmePath)) { throw "README not found: $readmePath" }
    $config = Get-GlmetaConfiguration -ConfigPath $ConfigPath
    $required = @($config.readme.requiredHeadings)
    if (-not $required.Count) { throw 'readme.requiredHeadings must contain at least one heading.' }

    $found = [System.Collections.Generic.Dictionary[string, int]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $insideFence = $false
    foreach ($line in [System.IO.File]::ReadLines($readmePath)) {
        if ($line -match '^\s*(```|~~~)') { $insideFence = -not $insideFence; continue }
        if ($insideFence -or $line -notmatch '^(#{1,6})\s+(.+?)\s*#*\s*$') { continue }
        $level = $Matches[1].Length
        $name = $Matches[2] -replace '<[^>]+>', '' -replace '[`*_~]', ''
        $name = [System.Net.WebUtility]::HtmlDecode($name).Trim()
        $key = "$level|$name"
        if ($found.ContainsKey($key)) { $found[$key]++ } else { $found[$key] = 1 }
    }

    $rows = [System.Collections.Generic.List[object]]::new($required.Count)
    foreach ($heading in $required) {
        $level = [int]$heading.level
        $name = [string]$heading.name
        $key = "$level|$name"
        $count = if ($found.ContainsKey($key)) { $found[$key] } else { 0 }
        $passed = $count -eq 1
        $rows.Add([pscustomobject]@{ Level = $level; Heading = $name; Count = $count; Passed = $passed })
    }
    if (-not $Quiet) {
        [Console]::WriteLine((Format-AnsiText -Text 'README REQUIREMENTS' -Color @(0, 200, 255) -Bold))
        foreach ($row in $rows) {
            $state = if ($row.Passed) { 'OK  ' } elseif ($row.Count -eq 0) { 'MISS' } else { 'DUPL' }
            $color = if ($row.Passed) { @(80, 220, 150) } else { @(255, 90, 105) }
            [Console]::WriteLine("  $(Format-AnsiText -Text $state -Color $color -Bold)  H$($row.Level) $($row.Heading)")
        }
        $passedCount = @($rows | Where-Object Passed).Count
        [Console]::WriteLine("  RESULT  $passedCount/$($rows.Count) required headings present exactly once")
    }
    $missing = @($rows | Where-Object { -not $_.Passed })
    $duplicates = @($rows | Where-Object { $_.Count -gt 1 })
    return [pscustomobject]@{
        Ready = $missing.Count -eq 0
        Path = $readmePath
        Requirements = $rows.ToArray()
        Missing = @($missing | Where-Object { $_.Count -eq 0 })
        Duplicates = $duplicates
    }
}
