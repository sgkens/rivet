function Write-RivetRepositoryStatus {
    <#
    .SYNOPSIS
        Displays read-only rivet repository and release state.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [Parameter(Mandatory)][string]$ConfigPath
    )

    $config = Get-RivetConfiguration -ConfigPath $ConfigPath
    $version = Get-ConventionalCommitVersion -RepositoryRoot $RepositoryRoot
    $branch = (& git -C $RepositoryRoot branch --show-current).Trim()
    $head = (& git -C $RepositoryRoot rev-parse --short=12 HEAD).Trim()
    $upstream = (& git -C $RepositoryRoot rev-parse --abbrev-ref '@{upstream}' 2>$null)
    $ahead = 0; $behind = 0
    if ($LASTEXITCODE -eq 0) {
        $upstream = $upstream.Trim()
        $counts = (& git -C $RepositoryRoot rev-list --left-right --count 'HEAD...@{upstream}') -split '\s+'
        if ($counts.Count -ge 2) { $ahead = [int]$counts[0]; $behind = [int]$counts[1] }
    }
    $changes = @(& git -C $RepositoryRoot status --short --untracked-files=all)
    $suffix = [string]$config.tagging.releaseSuffix
    $prefix = [string]$config.tagging.prefix
    $snapshotTag = "$prefix$($version.Version)"
    $productionTag = "$snapshotTag$suffix"
    $null = & git -C $RepositoryRoot show-ref --verify --quiet "refs/tags/$productionTag"
    $productionExists = $LASTEXITCODE -eq 0
    $null = & git -C $RepositoryRoot show-ref --verify --quiet "refs/tags/$snapshotTag"
    $snapshotExists = $LASTEXITCODE -eq 0
    $palette = @{ Label = @(145, 155, 175); Project = @(80, 220, 150); Version = @(255, 195, 75); Good = @(80, 220, 150); Warning = @(255, 195, 75); Bad = @(255, 90, 105); Text = @(220, 225, 235) }
    function Write-StatusField([string]$Label, [string]$Value, [int[]]$Color = $palette.Text) {
        [Console]::WriteLine("$(Format-AnsiText -Text ("  " + $Label.PadRight(12)) -Color $palette.Label)$(Format-AnsiText -Text $Value -Color $Color -Bold)")
    }
    [Console]::WriteLine((Format-AnsiText -Text 'RIVET STATUS' -Color @(0, 200, 255) -Bold))
    Write-StatusField 'project' $config.project.displayName $palette.Project
    Write-StatusField 'branch' $branch $palette.Text
    Write-StatusField 'head' $head $palette.Text
    Write-StatusField 'upstream' $(if ($upstream) { "$upstream | ahead $ahead | behind $behind" } else { 'not configured' }) $(if (-not $upstream -or $behind) { $palette.Bad } elseif ($ahead) { $palette.Warning } else { $palette.Good })
    Write-StatusField 'worktree' $(if ($changes.Count) { "$($changes.Count) changed path(s)" } else { 'clean' }) $(if ($changes.Count) { $palette.Warning } else { $palette.Good })
    Write-StatusField 'baseline' $(if ($version.LastTag) { $version.LastTag } else { 'none' }) $palette.Project
    Write-StatusField 'version' "$($version.Version) ($($version.BumpType))" $palette.Version
    Write-StatusField 'production' "$productionTag$(if ($productionExists) { ' | already tagged' })" $(if ($productionExists) { $palette.Warning } else { $palette.Version })
    Write-StatusField 'snapshot' "$snapshotTag$(if ($snapshotExists) { ' | already tagged' })" $(if ($snapshotExists) { $palette.Warning } else { $palette.Version })
    return [pscustomobject]@{ Version = $version.Version; Branch = $branch; Ahead = $ahead; Behind = $behind; Changes = $changes.Count }
}
