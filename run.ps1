<#
.SYNOPSIS
    Runs repeatable repository metadata maintenance for a consuming repository.
.DESCRIPTION
    Synchronizes local repository metadata by default and renders one inline,
    colorized execution report. Remote GitLab synchronization remains opt-in.
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('help', 'menu', 'init', 'bootstrap', 'prep-release', 'doctor', 'status', 'version', 'readme')]
    [string]$Command,
    [switch]$Help,
    [switch]$Menu,
    [switch]$Init,
    [switch]$Bootstrap,
    [switch]$PrepRelease,
    [switch]$Doctor,
    [switch]$Status,
    [switch]$VersionReport,
    [switch]$ValidateReadme,
    [Parameter(Position = 1)]
    [Alias('Param')]
    [string]$HelpParameter,
    [switch]$SkipVersion,
    [switch]$SkipReadmeMetadata,
    [switch]$SkipTableOfContents,
    [switch]$SkipReadmeValidation,
    [switch]$UpdateReleaseDocs,
    [switch]$FinalizeRelease,
    [switch]$UpdateChangelogJson,
    [switch]$UpdateMergeRequest,
    [switch]$CreateGitLabMergeRequest,
    [switch]$UpdateGitLabMergeRequest,
    [string]$ReleaseVersion,
    [string]$FromTag,
    [string]$MergeTargetBranch = 'main',
    [switch]$IncludeCommitHash = $true,
    [switch]$IncludeAuthor = $true,
    [switch]$SyncGitLabMetadata,
    [switch]$DeleteMissingLabels,
    [switch]$Commit,
    [string]$CommitType,
    [string]$CommitScope,
    [string]$CommitDescription,
    [string[]]$CommitFiles,
    [switch]$CommitAll,
    [switch]$Tag,
    [switch]$Snapshot,
    [switch]$TagForce,
    [ValidatePattern('^v?\d+\.\d+\.\d+$')][string]$TagVersion,
    [Alias('glo')][switch]$GitLog,
    [ValidateRange(1, 500)][int]$GitLogCount = 25,
    [switch]$GitLogAll,
    [switch]$GitLogNoMerges,
    [string]$RepositoryRoot,
    [string]$ConfigPath,
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($Command -eq 'help' -or $Help -or $PSBoundParameters.ContainsKey('HelpParameter')) {
    $helpScript = [System.IO.Path]::Combine($PSScriptRoot, 'help.ps1')
    if (-not [string]::IsNullOrWhiteSpace($HelpParameter) -and $HelpParameter -ine 'help') {
        & $helpScript -Param $HelpParameter
    } else {
        & $helpScript
    }
    return
}

$repositoryProbe = if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) { (Get-Location).Path } else { $RepositoryRoot }
$gitRoot = @(& git -C $repositoryProbe rev-parse --show-toplevel 2>$null)
if ($LASTEXITCODE -ne 0 -or -not $gitRoot.Count) { throw 'glmeta must run from inside a Git repository.' }
$repositoryRoot = [System.IO.Path]::GetFullPath(([string]$gitRoot[0]).Trim())
$resolvedConfigPath = if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
    [System.IO.Path]::Combine($repositoryRoot, 'repo_config.json')
} else {
    [System.IO.Path]::GetFullPath($ConfigPath)
}

if ($Command -eq 'menu' -or $Menu) {
    $menuScriptsRoot = [System.IO.Path]::Combine($PSScriptRoot, 'scripts')
    . ([System.IO.Path]::Combine($menuScriptsRoot, 'asciitokenizer.ps1'))
    . ([System.IO.Path]::Combine($menuScriptsRoot, 'smenu.ps1'))
    . ([System.IO.Path]::Combine($menuScriptsRoot, 'Invoke-GlmetaMenu.ps1'))
    Invoke-GlmetaMenu -RunnerPath $PSCommandPath -ConfigPath $resolvedConfigPath -RepositoryRoot $repositoryRoot
    return
}

$asciiBanner = @'
          /$$                           /$$
          | $$                          | $$
  /$$$$$$ | $$ /$$$$$$/$$$$   /$$$$$$  /$$$$$$    /$$$$$$
 /$$__  $$| $$| $$_  $$_  $$ /$$__  $$|_  $$_/   |____  $$
| $$  \ $$| $$| $$ \ $$ \ $$| $$$$$$$$  | $$      /$$$$$$$
| $$  | $$| $$| $$ | $$ | $$| $$_____/  | $$ /$$ /$$__  $$
|  $$$$$$$| $$| $$ | $$ | $$|  $$$$$$$  |  $$$$/|  $$$$$$$
\____  $$|__/|__/ |__/ |__/ \_______/   \___/   \_______/
      /$$ / GitLab Metadata Automation
|  $$$$$$/  Repository maintenance runner
 \______/   Local by default; remote sync is opt-in
'@

$scriptsRoot = [System.IO.Path]::Combine($PSScriptRoot, 'scripts')
. ([System.IO.Path]::Combine($scriptsRoot, 'asciitokenizer.ps1'))
. ([System.IO.Path]::Combine($scriptsRoot, 'lazylog.ps1'))
. ([System.IO.Path]::Combine($scriptsRoot, 'Get-GlmetaConfiguration.ps1'))
. ([System.IO.Path]::Combine($scriptsRoot, 'Initialize-GlmetaRepository.ps1'))
. ([System.IO.Path]::Combine($scriptsRoot, 'ConvertFrom-ConventionalCommit.ps1'))
. ([System.IO.Path]::Combine($scriptsRoot, 'Get-ConventionalCommitVersion.ps1'))
. ([System.IO.Path]::Combine($scriptsRoot, 'Update-JSLibSemver.ps1'))
. ([System.IO.Path]::Combine($scriptsRoot, 'jsheader.ps1'))
. ([System.IO.Path]::Combine($scriptsRoot, 'New-MarkdownTOC.ps1'))
. ([System.IO.Path]::Combine($scriptsRoot, 'Update-ReleaseDocumentation.ps1'))
. ([System.IO.Path]::Combine($scriptsRoot, 'Update-MergeRequestDocumentation.ps1'))
. ([System.IO.Path]::Combine($scriptsRoot, 'Invoke-GitLabMergeRequest.ps1'))
. ([System.IO.Path]::Combine($scriptsRoot, 'smenu.ps1'))
. ([System.IO.Path]::Combine($scriptsRoot, 'Invoke-RepositoryCommit.ps1'))
. ([System.IO.Path]::Combine($scriptsRoot, 'Write-PrettyGitLog.ps1'))
. ([System.IO.Path]::Combine($scriptsRoot, 'Invoke-RepositoryTag.ps1'))
. ([System.IO.Path]::Combine($scriptsRoot, 'Write-GlmetaVersionReport.ps1'))
. ([System.IO.Path]::Combine($scriptsRoot, 'Write-GlmetaRepositoryStatus.ps1'))
. ([System.IO.Path]::Combine($scriptsRoot, 'Test-GlmetaRepository.ps1'))
. ([System.IO.Path]::Combine($scriptsRoot, 'Test-ReadmeStructure.ps1'))

$reportRows = [System.Collections.Generic.List[object]]::new(7)
$failure = $null
$prepReleaseDefaultCommitSelection = $false
$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

function Add-ReportRow {
    param(
        [Parameter(Mandatory)][string]$State,
        [Parameter(Mandatory)][string]$Label,
        [Parameter(Mandatory)][string]$Detail
    )

    $reportRows.Add([PSCustomObject]@{ State = $State; Label = $Label; Detail = $Detail })
}

$bannerTokens = ConvertTo-AsciiTokens -Lines ($asciiBanner -split '\r?\n') -Connectivity 8
foreach ($line in @(ConvertTo-GradientAsciiLines -TokenObject $bannerTokens -Mode Horizontal -StartColor @(0, 180, 255) -EndColor @(255, 60, 180))) {
    [Console]::WriteLine($line)
}
[Console]::WriteLine('')
if ($Command -eq 'init' -or $Init) {
    $templateRoot = [System.IO.Path]::Combine($PSScriptRoot, 'templates', 'js')
    $null = Initialize-GlmetaRepository -RepositoryRoot $repositoryRoot -TemplateRoot $templateRoot -DryRun:$DryRun -Confirm:$false
    return
}
if ($Command -eq 'bootstrap' -or $Bootstrap) {
    $templateRoot = [System.IO.Path]::Combine($PSScriptRoot, 'templates', 'js')
    $null = Initialize-GlmetaRepository -RepositoryRoot $repositoryRoot -TemplateRoot $templateRoot -DryRun:$DryRun -Confirm:$false
    if ($DryRun) {
        [Console]::WriteLine((Format-AnsiText -Text 'GitLab metadata synchronization will run after configuration is applied.' -Color @(145, 155, 175)))
        return
    }
    $syncScript = [System.IO.Path]::Combine($scriptsRoot, 'Sync-GitLabRepositoryMetadata.ps1')
    $null = & $syncScript -ConfigPath $resolvedConfigPath -Confirm:$false
    return
}
if ($Command -eq 'doctor' -or $Doctor) {
    $doctorResult = Test-GlmetaRepository -RepositoryRoot $repositoryRoot -ConfigPath $resolvedConfigPath
    if (-not $doctorResult.Ready) { throw "glmeta doctor found $(@($doctorResult.Failures).Count) failed check(s)." }
    return
}
if ($Command -eq 'status' -or $Status) {
    $null = Write-GlmetaRepositoryStatus -RepositoryRoot $repositoryRoot -ConfigPath $resolvedConfigPath
    return
}
if ($Command -eq 'version' -or $VersionReport) {
    $null = Write-GlmetaVersionReport -RepositoryRoot $repositoryRoot
    return
}
if ($Command -eq 'readme' -or $ValidateReadme) {
    $readmeResult = Test-ReadmeStructure -RepositoryRoot $repositoryRoot -ConfigPath $resolvedConfigPath
    if (-not $readmeResult.Ready) { throw "README is missing $(@($readmeResult.Missing).Count) required heading(s)." }
    return
}
if ($GitLog) {
    Write-PrettyGitLog -RepositoryRoot $repositoryRoot -Count $GitLogCount -All:$GitLogAll -NoMerges:$GitLogNoMerges -Scope $CommitScope
    return
}
if ($Snapshot -and -not $Tag) { throw '-Snapshot requires -Tag.' }
if ($TagForce -and -not $Tag) { throw '-TagForce requires -Tag.' }
if (-not [string]::IsNullOrWhiteSpace($TagVersion) -and -not $Tag) { throw '-TagVersion requires -Tag.' }
if ($CreateGitLabMergeRequest -and $UpdateGitLabMergeRequest) { throw '-CreateGitLabMergeRequest and -UpdateGitLabMergeRequest are mutually exclusive.' }
if ($UpdateChangelogJson -and -not ($UpdateReleaseDocs -or $FinalizeRelease -or $PrepRelease -or $Command -eq 'prep-release')) { throw '-UpdateChangelogJson requires -UpdateReleaseDocs, -FinalizeRelease, or prep-release.' }
if ($Tag) {
    $tagParameters = @{
        RepositoryRoot = $repositoryRoot
        ConfigPath = $resolvedConfigPath
        Snapshot = $Snapshot
        Force = $TagForce
        DryRun = $DryRun
    }
    if (-not [string]::IsNullOrWhiteSpace($TagVersion)) { $tagParameters.Version = $TagVersion }
    $null = Invoke-RepositoryTag @tagParameters
    return
}

if ($Command -eq 'prep-release' -or $PrepRelease) {
    $PrepRelease = $true
    $FinalizeRelease = $true
    $UpdateMergeRequest = $true
    if ($Commit -and -not $CommitAll -and -not @($CommitFiles).Count) {
        $prepReleaseDefaultCommitSelection = $true
    }
}
[Console]::WriteLine((Format-AnsiText -Text 'ACTION LOG' -Color @(0, 200, 255) -Bold))

if ($SkipVersion) {
    Write-LazyLog -Level skip -Title 'VERSION' -Message 'Skipped by command switch.' -Log
    Add-ReportRow -State 'SKIP' -Label 'VERSION' -Detail 'disabled by switch'
} else {
    try {
        Write-LazyLog -Level act -Title 'VERSION' -Message 'Calculating version from Conventional Commits.' -Log
        $version = Get-ConventionalCommitVersion -RepositoryRoot $repositoryRoot
        $null = @(Update-JSLibSemver -Version $version.Version -RepositoryRoot $repositoryRoot -DryRun:$DryRun *>&1)
        Write-LazyLog -Level suc -Title 'VERSION' -Message "Resolved $($version.Version) using a $($version.BumpType) bump across $($version.CommitsScanned) commits." -Log
        Add-ReportRow -State 'OK' -Label 'VERSION' -Detail "$($version.Version) | $($version.BumpType) | $($version.CommitsScanned) commits"
    } catch {
        Write-LazyLog -Level fail -Title 'VERSION' -Message $_.Exception.Message -Log
        Add-ReportRow -State 'FAIL' -Label 'VERSION' -Detail $_.Exception.Message
        $failure = $_
    }
}

if ($SkipReadmeMetadata) {
    Write-LazyLog -Level skip -Title 'HEADER' -Message 'Skipped by command switch.' -Log
    Add-ReportRow -State 'SKIP' -Label 'HEADER' -Detail 'disabled by switch'
} else {
    try {
        Write-LazyLog -Level act -Title 'HEADER' -Message 'Rendering the centered README header from repository configuration.' -Log
        $null = @(Update-JSHeader -RepositoryRoot $repositoryRoot -ConfigPath $resolvedConfigPath -DryRun:$DryRun *>&1)
        $modeDetail = if ($DryRun) { 'configuration-driven header previewed' } else { 'configuration-driven header synchronized' }
        Write-LazyLog -Level suc -Title 'HEADER' -Message $modeDetail -Log
        Add-ReportRow -State 'OK' -Label 'HEADER' -Detail $modeDetail
    } catch {
        Write-LazyLog -Level fail -Title 'HEADER' -Message $_.Exception.Message -Log
        Add-ReportRow -State 'FAIL' -Label 'HEADER' -Detail $_.Exception.Message
        if ($null -eq $failure) { $failure = $_ }
    }
}

if ($SkipTableOfContents) {
    Write-LazyLog -Level skip -Title 'TOC' -Message 'Skipped by command switch.' -Log
    Add-ReportRow -State 'SKIP' -Label 'TOC' -Detail 'disabled by switch'
} else {
    try {
        Write-LazyLog -Level act -Title 'TOC' -Message 'Scanning README headings and synchronizing the generated table of contents.' -Log
        $readmePath = [System.IO.Path]::Combine($repositoryRoot, 'README.md')
        $null = @(New-MarkdownTOC -Path $readmePath -MinLevel 2 -MaxLevel 4 -AutoUpdate -DryRun:$DryRun *>&1)
        $modeDetail = if ($DryRun) { 'README structure previewed' } else { 'README table of contents synchronized' }
        Write-LazyLog -Level suc -Title 'TOC' -Message $modeDetail -Log
        Add-ReportRow -State 'OK' -Label 'TOC' -Detail $modeDetail
    } catch {
        Write-LazyLog -Level fail -Title 'TOC' -Message $_.Exception.Message -Log
        Add-ReportRow -State 'FAIL' -Label 'TOC' -Detail $_.Exception.Message
        if ($null -eq $failure) { $failure = $_ }
    }
}

if ($SkipReadmeValidation) {
    Write-LazyLog -Level skip -Title 'README' -Message 'Required-heading validation skipped by command switch.' -Log
    Add-ReportRow -State 'SKIP' -Label 'README' -Detail 'required-heading validation disabled'
} else {
    try {
        Write-LazyLog -Level act -Title 'README' -Message 'Validating required JavaScript library sections.' -Log
        $readmeResult = Test-ReadmeStructure -RepositoryRoot $repositoryRoot -ConfigPath $resolvedConfigPath -Quiet
        if (-not $readmeResult.Ready) {
            $missingNames = @($readmeResult.Missing | ForEach-Object { "H$($_.Level) $($_.Heading)" })
            throw "Missing required README headings: $($missingNames -join ', ')"
        }
        Write-LazyLog -Level suc -Title 'README' -Message "$(@($readmeResult.Requirements).Count) required headings present." -Log
        Add-ReportRow -State 'OK' -Label 'README' -Detail "$(@($readmeResult.Requirements).Count) required headings present"
    } catch {
        Write-LazyLog -Level fail -Title 'README' -Message $_.Exception.Message -Log
        Add-ReportRow -State 'FAIL' -Label 'README' -Detail $_.Exception.Message
        if ($null -eq $failure) { $failure = $_ }
    }
}

if (-not ($UpdateReleaseDocs -or $FinalizeRelease)) {
    Write-LazyLog -Level skip -Title 'RELEASE' -Message 'Release-document generation was not requested.' -Log
    Add-ReportRow -State 'SKIP' -Label 'RELEASE' -Detail 'release-document generation not requested'
} else {
    try {
        $rangeMessage = if ($FromTag) { "the explicit $FromTag baseline" } else { 'the latest reachable GitLab release tag' }
        Write-LazyLog -Level act -Title 'RELEASE' -Message "Generating changelog and release notes from $rangeMessage." -Log
        $releaseParameters = @{
            RepositoryRoot = $repositoryRoot
            ConfigPath     = $resolvedConfigPath
            Finalize       = $FinalizeRelease
            IncludeCommitHash = $IncludeCommitHash
            IncludeAuthor  = $IncludeAuthor
            WriteChangelogJson = $UpdateChangelogJson
            DryRun         = $DryRun
        }
        if (-not [string]::IsNullOrWhiteSpace($FromTag)) { $releaseParameters.FromTag = $FromTag }
        if (-not [string]::IsNullOrWhiteSpace($ReleaseVersion)) { $releaseParameters.Version = $ReleaseVersion }
        if (-not [string]::IsNullOrWhiteSpace($CommitScope)) { $releaseParameters.Scope = $CommitScope }
        $null = @(Update-ReleaseDocumentation @releaseParameters *>&1)
        $modeDetail = if ($DryRun) { 'release documentation previewed' } elseif ($FinalizeRelease) { 'release documentation finalized' } else { 'draft release documentation synchronized' }
        Write-LazyLog -Level suc -Title 'RELEASE' -Message $modeDetail -Log
        Add-ReportRow -State 'OK' -Label 'RELEASE' -Detail $modeDetail
    } catch {
        Write-LazyLog -Level fail -Title 'RELEASE' -Message $_.Exception.Message -Log
        Add-ReportRow -State 'FAIL' -Label 'RELEASE' -Detail $_.Exception.Message
        if ($null -eq $failure) { $failure = $_ }
    }
}

if (-not $UpdateMergeRequest) {
    Write-LazyLog -Level skip -Title 'MR' -Message 'Merge-request generation was not requested.' -Log
    Add-ReportRow -State 'SKIP' -Label 'MR' -Detail 'merge-request generation not requested'
} else {
    try {
        Write-LazyLog -Level act -Title 'MR' -Message 'Generating mr.md from its managed template sections.' -Log
        $mergeRequestParameters = @{
            RepositoryRoot   = $repositoryRoot
            ConfigPath       = $resolvedConfigPath
            TargetBranch     = $MergeTargetBranch
            IncludeCommitHash = $IncludeCommitHash
            IncludeAuthor    = $IncludeAuthor
            DryRun           = $DryRun
        }
        if (-not [string]::IsNullOrWhiteSpace($FromTag)) { $mergeRequestParameters.FromTag = $FromTag }
        if (-not [string]::IsNullOrWhiteSpace($ReleaseVersion)) { $mergeRequestParameters.Version = $ReleaseVersion }
        if (-not [string]::IsNullOrWhiteSpace($CommitScope)) { $mergeRequestParameters.Scope = $CommitScope }
        $null = @(Update-MergeRequestDocumentation @mergeRequestParameters *>&1)
        $modeDetail = if ($DryRun) { 'merge-request documentation previewed' } else { 'merge-request documentation synchronized' }
        Write-LazyLog -Level suc -Title 'MR' -Message $modeDetail -Log
        Add-ReportRow -State 'OK' -Label 'MR' -Detail $modeDetail
    } catch {
        Write-LazyLog -Level fail -Title 'MR' -Message $_.Exception.Message -Log
        Add-ReportRow -State 'FAIL' -Label 'MR' -Detail $_.Exception.Message
        if ($null -eq $failure) { $failure = $_ }
    }
}

$remoteMergeRequestMode = if ($CreateGitLabMergeRequest) { 'Create' } elseif ($UpdateGitLabMergeRequest) { 'Update' } else { $null }
if ($null -eq $remoteMergeRequestMode) {
    Write-LazyLog -Level skip -Title 'REMOTE MR' -Message 'GitLab merge-request publication was not requested.' -Log
    Add-ReportRow -State 'SKIP' -Label 'REMOTE MR' -Detail 'remote merge-request action not requested'
} elseif ($null -ne $failure) {
    Write-LazyLog -Level skip -Title 'REMOTE MR' -Message 'Skipped because an earlier action failed.' -Log
    Add-ReportRow -State 'SKIP' -Label 'REMOTE MR' -Detail 'earlier action failed'
} else {
    try {
        Write-LazyLog -Level act -Title 'REMOTE MR' -Message "$remoteMergeRequestMode GitLab merge request from mr.md." -Log
        $remoteResult = Invoke-GitLabMergeRequest -RepositoryRoot $repositoryRoot -ConfigPath $resolvedConfigPath -Mode $remoteMergeRequestMode -DryRun:$DryRun
        $remoteDetail = if ($DryRun) { "$($remoteMergeRequestMode.ToLowerInvariant()) previewed" } else { "$($remoteMergeRequestMode.ToLowerInvariant())d GitLab merge request !$($remoteResult.Iid)" }
        Write-LazyLog -Level suc -Title 'REMOTE MR' -Message $remoteDetail -Log
        Add-ReportRow -State 'OK' -Label 'REMOTE MR' -Detail $remoteDetail
    } catch {
        Write-LazyLog -Level fail -Title 'REMOTE MR' -Message $_.Exception.Message -Log
        Add-ReportRow -State 'FAIL' -Label 'REMOTE MR' -Detail $_.Exception.Message
        if ($null -eq $failure) { $failure = $_ }
    }
}

if (-not $SyncGitLabMetadata) {
    Write-LazyLog -Level skip -Title 'GITLAB' -Message 'Remote synchronization was not requested.' -Log
    Add-ReportRow -State 'SKIP' -Label 'GITLAB' -Detail 'remote synchronization not requested'
} else {
    try {
        Write-LazyLog -Level act -Title 'GITLAB' -Message 'Reading project metadata and evaluating remote changes.' -Log
        $syncScript = [System.IO.Path]::Combine($scriptsRoot, 'Sync-GitLabRepositoryMetadata.ps1')
        $remoteMessages = @(& $syncScript -ConfigPath $resolvedConfigPath -DryRun:$DryRun -DeleteMissing:$DeleteMissingLabels -Confirm:$false *>&1)
        $action = if ($DryRun) { 'remote actions inspected' } else { 'remote actions completed' }
        Write-LazyLog -Level suc -Title 'GITLAB' -Message "$($remoteMessages.Count) $action." -Log
        Add-ReportRow -State 'OK' -Label 'GITLAB' -Detail "$($remoteMessages.Count) $action"
    } catch {
        Write-LazyLog -Level fail -Title 'GITLAB' -Message $_.Exception.Message -Log
        Add-ReportRow -State 'FAIL' -Label 'GITLAB' -Detail $_.Exception.Message
        if ($null -eq $failure) { $failure = $_ }
    }
}

if (-not $Commit) {
    Write-LazyLog -Level skip -Title 'COMMIT' -Message 'Interactive commit was not requested.' -Log
    Add-ReportRow -State 'SKIP' -Label 'COMMIT' -Detail 'interactive commit not requested'
} elseif ($null -ne $failure) {
    Write-LazyLog -Level skip -Title 'COMMIT' -Message 'Skipped because an earlier action failed.' -Log
    Add-ReportRow -State 'SKIP' -Label 'COMMIT' -Detail 'earlier action failed'
} else {
    try {
        Write-LazyLog -Level act -Title 'COMMIT' -Message 'Preparing a Conventional Commit review.' -Log
        $commitParameters = @{
            RepositoryRoot = $repositoryRoot
            ConfigPath     = $resolvedConfigPath
            DryRun         = $DryRun
        }
        if (-not [string]::IsNullOrWhiteSpace($CommitType)) { $commitParameters.Type = $CommitType }
        if (-not [string]::IsNullOrWhiteSpace($CommitScope)) { $commitParameters.Scope = $CommitScope }
        if (-not [string]::IsNullOrWhiteSpace($CommitDescription)) { $commitParameters.Description = $CommitDescription }
        if ($prepReleaseDefaultCommitSelection) {
            $releaseFileSet = [System.Collections.Generic.HashSet[string]]::new(@('package.json', 'package-lock.json', 'jsr.jsonc', 'CHANGELOG.md', 'release-notes.md', 'docs/data/changelog.json', 'README.md', 'README-npm.md'), [System.StringComparer]::Ordinal)
            $changedReleaseFiles = @(& git -C $repositoryRoot status --porcelain=v1 --untracked-files=all) | ForEach-Object {
                if ($_.Length -gt 3) { $_.Substring(3).Trim('"') }
            } | Where-Object { $releaseFileSet.Contains($_) }
            if (-not @($changedReleaseFiles).Count) { throw 'Prep Release did not produce any tracked release-file changes to commit.' }
            $commitParameters.Files = @($changedReleaseFiles)
        } elseif (@($CommitFiles).Count) { $commitParameters.Files = $CommitFiles }
        if ($CommitAll) { $commitParameters.All = $true }
        $commitResult = Invoke-RepositoryCommit @commitParameters
        $commitDetail = if ($commitResult.Submitted) { "submitted | $($commitResult.Subject)" } elseif ($DryRun) { "previewed | $($commitResult.Subject)" } else { 'cancelled by user' }
        Write-LazyLog -Level $(if ($commitResult.Submitted) { 'suc' } else { 'skip' }) -Title 'COMMIT' -Message $commitDetail -Log
        Add-ReportRow -State $(if ($commitResult.Submitted) { 'OK' } else { 'SKIP' }) -Label 'COMMIT' -Detail $commitDetail
    } catch {
        Write-LazyLog -Level fail -Title 'COMMIT' -Message $_.Exception.Message -Log
        Add-ReportRow -State 'FAIL' -Label 'COMMIT' -Detail $_.Exception.Message
        if ($null -eq $failure) { $failure = $_ }
    }
}

$stopwatch.Stop()
$mode = if ($DryRun) { 'DRY RUN' } else { 'APPLY' }
[Console]::WriteLine('')
[Console]::WriteLine((Format-AnsiText -Text 'FINAL REPORT' -Color @(0, 200, 255) -Bold))
[Console]::WriteLine((Format-AnsiText -Text "MODE  $mode" -Color @(145, 155, 175)))

$stateLevels = @{
    OK   = 'suc'
    SKIP = 'skip'
    FAIL = 'fail'
}
foreach ($row in $reportRows) {
    [Console]::WriteLine((Format-LazyLog -Level $stateLevels[$row.State] -Title $row.Label -Message $row.Detail))
}
[Console]::WriteLine((Format-AnsiText -Text ("ELAPSED  {0:N0} ms" -f $stopwatch.Elapsed.TotalMilliseconds) -Color @(145, 155, 175)))

if ($null -ne $failure) {
    throw $failure
}
