<#
.SYNOPSIS
    Writes a dense ANSI Git history and repository summary.
.DESCRIPTION
    Reads one Git log stream containing commit metadata and numstat records,
    joins the statistics onto each commit line, and prints repository, branch,
    upstream, worktree, author, signature, merge, and change totals.
.PARAMETER RepositoryRoot
    Git repository to inspect.
.PARAMETER Count
    Maximum commits to display.
.PARAMETER All
    Includes commits from every local and remote ref.
.PARAMETER NoMerges
    Omits merge commits.
.EXAMPLE
    Write-PrettyGitLog -RepositoryRoot $PWD -Count 40
#>
function Write-PrettyGitLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [ValidateRange(1, 500)][int]$Count = 25,
        [switch]$All,
        [switch]$NoMerges,
        [string]$Scope
    )

    $repositoryPath = [System.IO.Path]::GetFullPath($RepositoryRoot)
    $insideWorkTree = & git -C $repositoryPath rev-parse --is-inside-work-tree 2>$null
    if ($LASTEXITCODE -ne 0 -or $insideWorkTree -ne 'true') { throw "Not a Git worktree: $repositoryPath" }

    $branch = (& git -C $repositoryPath branch --show-current).Trim()
    if ([string]::IsNullOrWhiteSpace($branch)) { $branch = '(detached HEAD)' }
    $head = (& git -C $repositoryPath rev-parse --short=12 HEAD).Trim()
    $upstream = (& git -C $repositoryPath rev-parse --abbrev-ref '@{upstream}' 2>$null)
    if ($LASTEXITCODE -ne 0) { $upstream = $null } else { $upstream = $upstream.Trim() }
    $ahead = 0
    $behind = 0
    if ($upstream) {
        $counts = ((& git -C $repositoryPath rev-list --left-right --count 'HEAD...@{upstream}') -split '\s+')
        if ($counts.Count -ge 2) { $ahead = [int]$counts[0]; $behind = [int]$counts[1] }
    }
    $worktree = @(& git -C $repositoryPath status --short --untracked-files=all)

    $gitArguments = [System.Collections.Generic.List[string]]::new()
    $readCount = if ([string]::IsNullOrWhiteSpace($Scope)) { $Count } else { 5000 }
    $gitArguments.AddRange([string[]]@('-C', $repositoryPath, 'log', "--max-count=$readCount", '--date=iso-strict', '--numstat', '--format=__RIVET_COMMIT__%x1f%H%x1f%h%x1f%D%x1f%aN%x1f%aE%x1f%cI%x1f%cr%x1f%G?%x1f%p%x1f%s'))
    if ($All) { $gitArguments.Add('--all') }
    if ($NoMerges) { $gitArguments.Add('--no-merges') }
    $rawLog = @(& git @gitArguments)
    if ($LASTEXITCODE -ne 0) { throw 'Unable to read Git history.' }

    $commits = [System.Collections.Generic.List[object]]::new()
    $current = $null
    foreach ($line in $rawLog) {
        if ($line.StartsWith('__RIVET_COMMIT__')) {
            if ($null -ne $current) { $commits.Add($current) }
            $fields = $line.Split([char]0x1f)
            $current = [pscustomobject]@{
                Hash = $fields[1]; ShortHash = $fields[2]; Refs = $fields[3]
                Author = $fields[4]; Email = $fields[5]; Date = $fields[6]
                RelativeDate = $fields[7]; Signature = $fields[8]
                Parents = $fields[9]; Subject = $fields[10]
                Files = 0; Insertions = 0L; Deletions = 0L; BinaryFiles = 0
            }
            continue
        }
        if ($null -eq $current -or [string]::IsNullOrWhiteSpace($line)) { continue }
        $stat = $line -split "`t", 3
        if ($stat.Count -ne 3) { continue }
        $current.Files++
        if ($stat[0] -eq '-' -or $stat[1] -eq '-') { $current.BinaryFiles++ } else {
            $current.Insertions += [long]$stat[0]
            $current.Deletions += [long]$stat[1]
        }
    }
    if ($null -ne $current) { $commits.Add($current) }
    if (-not [string]::IsNullOrWhiteSpace($Scope)) {
        $filtered = [System.Collections.Generic.List[object]]::new()
        foreach ($commit in $commits) {
            $parsedCommit = ConvertFrom-ConventionalCommit -Subject $commit.Subject
            if ($parsedCommit.Scope -eq $Scope.ToLowerInvariant()) { $filtered.Add($commit) }
            if ($filtered.Count -ge $Count) { break }
        }
        $commits = $filtered
    }

    $esc = [char]27
    $palette = @{
        Accent = @(0, 200, 255); Hash = @(255, 195, 75); Refs = @(210, 120, 255)
        Author = @(80, 220, 150); Muted = @(145, 155, 175); Text = @(220, 225, 235)
        Bad = @(255, 90, 105)
    }
    function Paint-GitLogText([string]$Text, [int[]]$Color, [switch]$Bold) {
        $weight = if ($Bold) { '1;' } else { '' }
        return "$esc[${weight}38;2;$($Color[0]);$($Color[1]);$($Color[2])m$Text$esc[0m"
    }

    [Console]::WriteLine((Paint-GitLogText -Text 'REPOSITORY DETAIL' -Color $palette.Accent -Bold))
    [Console]::WriteLine("  $(Paint-GitLogText 'path' $palette.Muted)      $repositoryPath")
    [Console]::WriteLine("  $(Paint-GitLogText 'branch' $palette.Muted)    $branch  $(Paint-GitLogText $head $palette.Hash -Bold)")
    $upstreamDetail = if ($upstream) { "$upstream  ahead $ahead / behind $behind" } else { 'not configured' }
    [Console]::WriteLine("  $(Paint-GitLogText 'upstream' $palette.Muted)  $upstreamDetail")
    $worktreeDetail = if ($worktree.Count) { "$($worktree.Count) changed path(s)" } else { 'clean' }
    [Console]::WriteLine("  $(Paint-GitLogText 'worktree' $palette.Muted)  $worktreeDetail")
    [Console]::WriteLine('')
    $scopeDetail = if ($Scope) { " / scope $Scope" } else { '' }
    [Console]::WriteLine((Paint-GitLogText -Text "GIT HISTORY  newest first / $($commits.Count) shown$scopeDetail" -Color $palette.Accent -Bold))

    foreach ($commit in $commits) {
        $parentCount = if ([string]::IsNullOrWhiteSpace($commit.Parents)) { 0 } else { @($commit.Parents -split ' ').Count }
        $graph = if ($parentCount -gt 1) { 'M' } else { '*' }
        $refs = if ([string]::IsNullOrWhiteSpace($commit.Refs)) { '' } else { " $(Paint-GitLogText "[$($commit.Refs)]" $palette.Refs -Bold)" }
        $signatureColor = if ($commit.Signature -in @('G', 'U', 'X', 'Y', 'R')) { $palette.Author } elseif ($commit.Signature -eq 'N') { $palette.Muted } else { $palette.Bad }
        $signature = Paint-GitLogText "sig:$($commit.Signature)" $signatureColor
        $stats = "files:$($commit.Files) +$($commit.Insertions) -$($commit.Deletions)"
        if ($commit.BinaryFiles) { $stats += " bin:$($commit.BinaryFiles)" }
        $parents = if ($parentCount -gt 1) { " parents:$parentCount" } else { '' }
        $line = "$(Paint-GitLogText $graph $palette.Accent -Bold) $(Paint-GitLogText $commit.ShortHash $palette.Hash -Bold)$refs $(Paint-GitLogText $commit.Date $palette.Muted) ($(Paint-GitLogText $commit.RelativeDate $palette.Muted)) $(Paint-GitLogText "$($commit.Author) <$($commit.Email)>" $palette.Author) $signature $(Paint-GitLogText $commit.Subject $palette.Text -Bold) $(Paint-GitLogText "| $stats$parents" $palette.Muted)"
        [Console]::WriteLine($line)
    }

    $uniqueAuthors = if ($commits.Count) { @($commits | ForEach-Object Author | Sort-Object -Unique).Count } else { 0 }
    $mergeCount = @($commits | Where-Object { $_.Parents -match ' ' }).Count
    $signedCount = @($commits | Where-Object { $_.Signature -ne 'N' }).Count
    $totalFiles = if ($commits.Count) { ($commits | Measure-Object Files -Sum).Sum } else { 0 }
    $totalInsertions = if ($commits.Count) { ($commits | Measure-Object Insertions -Sum).Sum } else { 0 }
    $totalDeletions = if ($commits.Count) { ($commits | Measure-Object Deletions -Sum).Sum } else { 0 }
    [Console]::WriteLine('')
    [Console]::WriteLine((Paint-GitLogText -Text 'HISTORY DETAIL' -Color $palette.Accent -Bold))
    [Console]::WriteLine("  commits $($commits.Count) | authors $uniqueAuthors | merges $mergeCount | signed $signedCount | files $totalFiles | +$totalInsertions | -$totalDeletions")
    if ($worktree.Count) {
        [Console]::WriteLine((Paint-GitLogText -Text 'WORKTREE DETAIL' -Color $palette.Accent -Bold))
        foreach ($change in $worktree) { [Console]::WriteLine("  $change") }
    }
}
