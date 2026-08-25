function Write-GlmetaVersionReport {
    <#
    .SYNOPSIS
        Explains the repository's next version calculation.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$RepositoryRoot)

    $result = Get-ConventionalCommitVersion -RepositoryRoot $RepositoryRoot
    $range = if ($result.LastTag) { "$($result.LastTag)..HEAD" } else { 'complete history' }
    $palette = @{ Label = @(145, 155, 175); Identity = @(80, 220, 150); Version = @(255, 195, 75); Major = @(255, 90, 105); Minor = @(210, 120, 255); Patch = @(0, 200, 255); None = @(92, 102, 122) }
    function Write-VersionField([string]$Label, [string]$Value, [int[]]$Color) {
        [Console]::WriteLine("$(Format-AnsiText -Text ("  " + $Label.PadRight(11)) -Color $palette.Label)$(Format-AnsiText -Text $Value -Color $Color -Bold)")
    }
    [Console]::WriteLine((Format-AnsiText -Text 'VERSION REPORT' -Color @(0, 200, 255) -Bold))
    Write-VersionField 'baseline' $(if ($result.LastTag) { $result.LastTag } else { '0.0.0' }) $palette.Identity
    Write-VersionField 'range' $range $palette.Identity
    Write-VersionField 'commits' ([string]$result.CommitsScanned) $palette.Identity
    Write-VersionField 'bump' $result.BumpType $palette[$result.BumpType.Substring(0, 1).ToUpperInvariant() + $result.BumpType.Substring(1)]
    Write-VersionField 'result' $result.Version $palette.Version

    $subjects = if ($result.LastTag) { @(& git -C $RepositoryRoot log --no-merges '--format=%s' "$($result.LastTag)..HEAD") } else { @(& git -C $RepositoryRoot log --no-merges '--format=%s') }
    [Console]::WriteLine((Format-AnsiText -Text 'BUMP INPUTS' -Color @(210, 120, 255) -Bold))
    foreach ($subject in $subjects) {
        $parsed = ConvertFrom-ConventionalCommit -Subject $subject
        $effect = if ($parsed.Breaking) { 'major' } elseif ($parsed.Type -eq 'feat') { 'minor' } elseif ($parsed.Type -in @('fix', 'perf')) { 'patch' } else { 'none' }
        $effectKey = $effect.Substring(0, 1).ToUpperInvariant() + $effect.Substring(1)
        $effectText = ("  " + $effect.PadRight(7))
        [Console]::WriteLine("$(Format-AnsiText -Text $effectText -Color $palette[$effectKey] -Bold)$(Format-AnsiText -Text $subject -Color @(220, 225, 235))")
    }
    return $result
}
