<#
.SYNOPSIS
    Reviews, creates, and pushes a repository release tag.
.DESCRIPTION
    Calculates or accepts a SemVer version, creates an annotated production or
    snapshot tag, and pushes only that explicit tag ref. Production tags append
    the configured release suffix; snapshot tags use plain SemVer.
.PARAMETER RepositoryRoot
    Git repository whose HEAD will be tagged.
.PARAMETER ConfigPath
    glmeta configuration containing tagging defaults.
.PARAMETER Version
    Optional MAJOR.MINOR.PATCH override without the tag prefix.
.PARAMETER Snapshot
    Creates a plain SemVer snapshot tag without the production release suffix.
.PARAMETER DryRun
    Prints the complete review without creating or pushing a tag.
.EXAMPLE
    Invoke-RepositoryTag -RepositoryRoot $PWD -ConfigPath ./repo_config.json -DryRun
#>
function Invoke-RepositoryTag {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [Parameter(Mandatory)][string]$ConfigPath,
        [ValidatePattern('^v?\d+\.\d+\.\d+$')][string]$Version,
        [switch]$Snapshot,
        [switch]$Force,
        [switch]$DryRun
    )

    $repositoryPath = [System.IO.Path]::GetFullPath($RepositoryRoot)
    if (-not [System.IO.File]::Exists($ConfigPath)) { throw "glmeta config not found: $ConfigPath" }
    $config = [System.IO.File]::ReadAllText($ConfigPath) | ConvertFrom-Json
    $tagging = $config.tagging
    if ($null -eq $tagging) { throw "The glmeta config does not define a 'tagging' object." }
    $prefix = [string]$tagging.prefix
    $releaseSuffix = [string]$tagging.releaseSuffix
    $remote = [string]$tagging.remote
    if ($prefix -notmatch '^[A-Za-z0-9._-]*$') { throw 'tagging.prefix contains unsupported characters.' }
    if ($releaseSuffix -notmatch '^-[A-Za-z0-9][A-Za-z0-9.-]*$') { throw 'tagging.releaseSuffix must begin with a hyphen.' }
    if ($remote -notmatch '^[A-Za-z0-9._/-]+$') { throw 'tagging.remote contains unsupported characters.' }

    if ([string]::IsNullOrWhiteSpace($Version)) {
        $calculated = Get-ConventionalCommitVersion -RepositoryRoot $repositoryPath
        $Version = [string]$calculated.Version
    }
    $baseVersion = $Version.TrimStart('v')
    if ($baseVersion -notmatch '^\d+\.\d+\.\d+$') { throw "Tag version must be MAJOR.MINOR.PATCH; received '$Version'." }
    $tagName = "$prefix$baseVersion$(if ($Snapshot) { '' } else { $releaseSuffix })"

    $head = (& git -C $repositoryPath rev-parse HEAD).Trim()
    if ($LASTEXITCODE -ne 0) { throw 'Unable to resolve repository HEAD.' }
    $shortHead = (& git -C $repositoryPath rev-parse --short=12 HEAD).Trim()
    $subject = (& git -C $repositoryPath log -1 --format=%s).Trim()
    $branch = (& git -C $repositoryPath branch --show-current).Trim()
    if ([string]::IsNullOrWhiteSpace($branch)) { $branch = '(detached HEAD)' }
    $worktree = @(& git -C $repositoryPath status --short --untracked-files=all)
    $remoteUrl = & git -C $repositoryPath remote get-url $remote 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($remoteUrl)) { throw "Git remote '$remote' is not configured." }

    # Refresh remote-tracking refs before calculating release safety. A stale
    # local upstream can otherwise report a branch as synchronized incorrectly.
    $fetchOutput = @(& git -C $repositoryPath fetch --quiet $remote 2>&1)
    if ($LASTEXITCODE -ne 0) {
        $safeFetchOutput = @($fetchOutput | ForEach-Object { ([string]$_) -replace '(?i)(https?://)[^/@\s]+@', '$1***@' })
        throw "Unable to refresh remote '$remote'. $($safeFetchOutput -join ' ')"
    }

    $null = & git -C $repositoryPath show-ref --verify --quiet "refs/tags/$tagName"
    $localTagExists = $LASTEXITCODE -eq 0
    $localTagTarget = if ($localTagExists) { (& git -C $repositoryPath rev-list -n 1 $tagName).Trim() } else { $null }
    $upstream = & git -C $repositoryPath rev-parse --abbrev-ref '@{upstream}' 2>$null
    $upstreamState = 'not configured'
    $ahead = 0
    $behind = 0
    if ($LASTEXITCODE -eq 0) {
        $upstream = $upstream.Trim()
        $counts = ((& git -C $repositoryPath rev-list --left-right --count 'HEAD...@{upstream}') -split '\s+')
        if ($counts.Count -ge 2) { $ahead = [int]$counts[0]; $behind = [int]$counts[1] }
        $upstreamState = "$upstream | ahead $ahead | behind $behind"
    }

    $manifestVersions = [System.Collections.Generic.List[string]]::new(2)
    foreach ($manifestName in @('package.json', 'jsr.jsonc')) {
        $manifestPath = [System.IO.Path]::Combine($repositoryPath, $manifestName)
        if (-not [System.IO.File]::Exists($manifestPath)) { continue }
        $documentOptions = [System.Text.Json.JsonDocumentOptions]@{ CommentHandling = 'Skip'; AllowTrailingCommas = $true }
        $document = [System.Text.Json.JsonDocument]::Parse([System.IO.File]::ReadAllText($manifestPath), $documentOptions)
        try { $manifestVersions.Add("$manifestName=$($document.RootElement.GetProperty('version').GetString())") } finally { $document.Dispose() }
    }

    $mode = if ($Snapshot) { 'SNAPSHOT  CI validation only' } else { 'PRODUCTION  CI publish and release' }
    [Console]::WriteLine('')
    [Console]::WriteLine((Format-AnsiText -Text 'TAG REVIEW' -Color @(0, 200, 255) -Bold))
    [Console]::WriteLine((Format-AnsiText -Text $tagName -Color @(255, 195, 75) -Bold))
    [Console]::WriteLine("  mode       $mode")
    [Console]::WriteLine("  target     $shortHead  $subject")
    [Console]::WriteLine("  branch     $branch")
    [Console]::WriteLine("  remote     $remote")
    [Console]::WriteLine("  upstream   $upstreamState")
    [Console]::WriteLine("  manifests  $($manifestVersions -join ' | ')")
    [Console]::WriteLine("  worktree   $(if ($worktree.Count) { "$($worktree.Count) changed path(s)" } else { 'clean' })")
    if ($localTagExists) {
        $tagState = if ($localTagTarget -eq $head) { 'existing local tag targets HEAD; remote retry is available' } else { "existing local tag targets $localTagTarget" }
        [Console]::WriteLine((Format-AnsiText -Text "  warning    $tagState" -Color @(255, 90, 105) -Bold))
    }
    if ($worktree.Count) { foreach ($change in $worktree) { [Console]::WriteLine("             $change") } }

    $blockers = [System.Collections.Generic.List[string]]::new()
    if ($worktree.Count) { $blockers.Add('The worktree must be clean before creating a tag.') }
    if ([string]::IsNullOrWhiteSpace([string]$upstream)) { $blockers.Add('The current branch must have an upstream before tagging.') }
    if ($behind -ne 0) { $blockers.Add("The branch is behind or diverged; ahead $ahead, behind $behind. Pull or rebase before tagging.") }
    if ($localTagExists -and $localTagTarget -ne $head) { $blockers.Add("Tag '$tagName' already exists locally and does not target HEAD.") }
    $versionMismatches = @($manifestVersions | Where-Object { ($_ -split '=', 2)[1] -ne $baseVersion })
    if ($versionMismatches.Count) { $blockers.Add("Manifest versions must equal ${baseVersion}: $($versionMismatches -join ', ')") }

    $remoteTagOutput = @(& git -C $repositoryPath ls-remote --exit-code --tags $remote "refs/tags/$tagName" 2>&1)
    $remoteTagExitCode = $LASTEXITCODE
    $safeRemoteTagOutput = @($remoteTagOutput | ForEach-Object { ([string]$_) -replace '(?i)(https?://)[^/@\s]+@', '$1***@' })
    if ($remoteTagExitCode -eq 0) { $blockers.Add("Tag '$tagName' already exists on remote '$remote'.") }
    if ($remoteTagExitCode -ne 0 -and $remoteTagExitCode -ne 2) { throw "Unable to verify tag '$tagName' on remote '$remote'. $($safeRemoteTagOutput -join ' ')" }

    if ($DryRun) {
        foreach ($blocker in $blockers) { [Console]::WriteLine((Format-AnsiText -Text "  blocker    $blocker" -Color @(255, 90, 105) -Bold)) }
        return [pscustomobject]@{ Tag = $tagName; Snapshot = [bool]$Snapshot; Pushed = $false; Target = $head; Remote = $remote; Ready = $blockers.Count -eq 0; Blockers = $blockers.ToArray() }
    }
    if (-not $Force -and ([Console]::IsInputRedirected -or [Console]::IsOutputRedirected)) { throw 'Tag submission requires an interactive terminal, -Force, or -DryRun.' }
    if ($blockers.Count) { throw ($blockers -join ' ') }

    $pushPlan = if ($ahead -gt 0) { "push $branch ($ahead commit(s)), then create and push" } else { 'create and push' }
    $approved = $Force
    if (-not $approved) { $approved = (Read-Host "$pushPlan $mode tag '$tagName'? [y/N]") -match '^(?i:y|yes)$' }
    if (-not $approved) {
        return [pscustomobject]@{ Tag = $tagName; Snapshot = [bool]$Snapshot; Pushed = $false; Target = $head; Remote = $remote }
    }
    $message = if ($Snapshot) { "Snapshot $baseVersion" } else { "Release $baseVersion" }
    $createdLocalTag = $false
    if (-not $localTagExists) {
        $tagOutput = @(& git -C $repositoryPath tag --annotate $tagName --message $message)
        if ($LASTEXITCODE -ne 0) { throw "Unable to create tag '$tagName'. $($tagOutput -join ' ')" }
        $createdLocalTag = $true
    }
    $pushArguments = [System.Collections.Generic.List[string]]::new()
    $pushArguments.AddRange([string[]]@('-C', $repositoryPath, 'push'))
    if ($ahead -gt 0) { $pushArguments.Add('--atomic') }
    $pushArguments.Add($remote)
    if ($ahead -gt 0) {
        if ($branch -eq '(detached HEAD)') { throw 'A detached HEAD cannot be pushed as a release branch.' }
        $pushArguments.Add("refs/heads/${branch}:refs/heads/${branch}")
    }
    $pushArguments.Add("refs/tags/$tagName")
    $pushOutput = @(& git @pushArguments 2>&1)
    $safePushOutput = @($pushOutput | ForEach-Object { ([string]$_) -replace '(?i)(https?://)[^/@\s]+@', '$1***@' })
    if ($LASTEXITCODE -ne 0) {
        if ($createdLocalTag) { $null = & git -C $repositoryPath tag --delete $tagName }
        $rollbackDetail = if ($createdLocalTag) { ' The newly created local tag was removed.' } else { ' The pre-existing local tag was retained.' }
        throw "Atomic publication of '$tagName' failed.$rollbackDetail $($safePushOutput -join ' ')"
    }
    foreach ($line in $safePushOutput) { [Console]::WriteLine($line) }
    return [pscustomobject]@{ Tag = $tagName; Snapshot = [bool]$Snapshot; Pushed = $true; Target = $head; Remote = $remote }
}
