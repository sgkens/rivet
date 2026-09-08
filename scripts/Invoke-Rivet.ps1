<#
.SYNOPSIS
    Main router cmdlet for Rivet repository metadata and release automation.
.DESCRIPTION
    Invoke-Rivet provides a unified single entry point for all Rivet operations.
    It routes positional commands and switch parameters to underlying library
    helpers including configuration initialization, repository diagnostics,
    status inspection, version calculation, README and TOC maintenance, release
    documentation, merge requests, GitLab metadata synchronization, Conventional
    Commits, tag publication, Git history reporting, and the interactive TUI menu.

    Full tab-completion is provided for commands, parameters, commit types,
    commit scopes, changed files, tags, branches, and help topics.

.PARAMETER Command
    Positional command to execute: 'help', 'menu', 'init', 'bootstrap', 'prep-release',
    'doctor', 'status', 'version', 'readme', 'commit', 'tag', 'history', or 'glo'.

.PARAMETER Help
    Displays the Rivet reference manual or parameter help.

.PARAMETER Menu
    Opens the interactive full-screen Rivet TUI command center.

.PARAMETER Init
    Initializes repository configuration files from templates.

.PARAMETER Bootstrap
    Initializes configuration and synchronizes GitLab project metadata.

.PARAMETER Profile
    Installed repository profile used by init and bootstrap. Defaults to existing configuration or jsm.

.PARAMETER Manifest
    Repository-relative manifest path used by init and bootstrap.

.PARAMETER PrepRelease
    Prepares all standard release metadata (manifests, docs, and mr.md).

.PARAMETER Doctor
    Validates repository health, dependencies, and configuration readiness.

.PARAMETER Status
    Displays branch status, calculated SemVer, upstream status, and next tags.

.PARAMETER VersionReport
    Explains the Conventional Commit version bump calculation.

.PARAMETER ValidateReadme
    Validates required README headings defined in repository configuration.

.PARAMETER HelpParameter
    Parameter name or alias to display detailed documentation for.

.PARAMETER SkipVersion
    Skips SemVer calculation and manifest synchronization.

.PARAMETER SkipReadmeMetadata
    Skips README header synchronization.

.PARAMETER SkipTableOfContents
    Skips README table of contents generation.

.PARAMETER SkipReadmeValidation
    Skips required README heading validation.

.PARAMETER UpdateReleaseDocs
    Generates draft changelog and release notes.

.PARAMETER FinalizeRelease
    Generates finalized, dated release documentation.

.PARAMETER UpdateChangelogJson
    Generates curated docs/data/changelog.json data.

.PARAMETER UpdateMergeRequest
    Generates working mr.md document from templates.

.PARAMETER CreateGitLabMergeRequest
    Creates a new GitLab merge request from mr.md.

.PARAMETER UpdateGitLabMergeRequest
    Updates an existing open GitLab merge request from mr.md.

.PARAMETER ReleaseVersion
    Explicit SemVer version override for release documents and tags.

.PARAMETER FromTag
    Explicit reachable Git baseline ref for change calculation.

.PARAMETER MergeTargetBranch
    Target branch for merge requests (default: main).

.PARAMETER IncludeCommitHash
    Whether to include hyperlinked commit hashes in generated release notes (default: true).

.PARAMETER IncludeAuthor
    Whether to include author mentions in generated release notes (default: true).

.PARAMETER SyncGitLabMetadata
    Synchronizes project description, topics, and labels with GitLab.

.PARAMETER DeleteMissingLabels
    Removes remote GitLab labels not present in local configuration.

.PARAMETER Commit
    Opens the Conventional Commit review and staging workflow.

.PARAMETER CommitType
    Conventional Commit type (e.g. feat, fix, docs, chore).

.PARAMETER CommitScope
    Conventional Commit scope (e.g. core, cli, ui, docs).

.PARAMETER CommitDescription
    Conventional Commit subject description.

.PARAMETER CommitFiles
    Explicit array of changed files to stage for the commit.

.PARAMETER CommitAll
    Selects all changed files for the commit.

.PARAMETER Tag
    Creates and pushes a release or snapshot tag.

.PARAMETER Snapshot
    Creates a validation snapshot tag rather than a production release tag.

.PARAMETER TagForce
    Bypasses interactive keyboard confirmation when creating tags.

.PARAMETER TagVersion
    Explicit version override for the tag.

.PARAMETER GitLog
    Displays formatted, colorized Git history.

.PARAMETER GitLogCount
    Maximum number of commits to display in history view (default: 25).

.PARAMETER GitLogAll
    Includes all local and remote branches in history view.

.PARAMETER GitLogNoMerges
    Omits merge commits from history view.

.PARAMETER RepositoryRoot
    Path to the consuming repository working tree.

.PARAMETER ConfigPath
    Explicit path to repo_config.json configuration file.

.PARAMETER DryRun
    Previews operations without writing files or pushing changes.

.EXAMPLE
    Invoke-Rivet status

.EXAMPLE
    rivet prep-release -DryRun

.EXAMPLE
    Invoke-Rivet -Commit -CommitType feat -CommitScope core -CommitDescription 'add router cmdlet'

.EXAMPLE
    rivet help -Param Commit
#>
function Invoke-Rivet {
    [CmdletBinding(DefaultParameterSetName = 'Default')]
    [Alias('rivet')]
    param(
        [Parameter(Position = 0, ParameterSetName = 'Default')]
        [ArgumentCompleter([RivetCommandCompleter])]
        [ValidateSet('help', 'menu', 'init', 'bootstrap', 'prep-release', 'doctor', 'status', 'version', 'readme', 'commit', 'tag', 'history', 'glo', 'rebuild-changelog', 'flow', 'pipeline', 'work-items', 'issues', 'sync-issues', 'workitem', 'template', 'tasks', 'tasklist', 'wi', 'view', 'close', 'reopen', 'generate-list')]
        [string]$Command,

        [switch]$Help,
        [switch]$Menu,
        [switch]$Init,
        [switch]$Bootstrap,
        [switch]$Bun,
        [string]$Profile,
        [string]$Manifest,
        [switch]$PrepRelease,
        [switch]$Doctor,
        [switch]$Status,
        [switch]$VersionReport,
        [switch]$ValidateReadme,
        [Alias('Flow', 'Pipeline')][switch]$FlowGraph,
        [Alias('Issues', 'Tasks', 'Tasklist', 'Wi')][switch]$WorkItems,
        [switch]$SyncWorkItems,
        [switch]$PullIssues,
        [switch]$PushIssues,
        [switch]$ListIssues,
        [Alias('View')][switch]$ViewIssue,
        [Alias('Close')][switch]$CloseIssue,
        [Alias('Reopen')][switch]$ReopenIssue,
        [Alias('Index')][switch]$GenerateList,
        [Alias('Template')][switch]$NewIssue,
        [Alias('Iid')][int]$IssueIid = 0,
        [string]$IssueTitle,
        [string]$IssueDescription,
        [string[]]$IssueLabels,
        [string]$IssueState = 'opened',
        [string]$IssueMilestone,
        [switch]$ForceRefresh,

        [Parameter(Position = 1)]
        [Alias('Param')]
        [ArgumentCompleter([RivetHelpParamCompleter])]
        [string]$HelpParameter,

        [switch]$SkipVersion,
        [switch]$SkipReadmeMetadata,
        [switch]$SkipTableOfContents,
        [switch]$SkipReadmeValidation,
        [switch]$UpdateReleaseDocs,
        [switch]$FinalizeRelease,
        [Alias('Rebuild')][switch]$RebuildChangelog,
        [switch]$UpdateChangelogJson,
        [switch]$UpdateMergeRequest,
        [switch]$CreateGitLabMergeRequest,
        [switch]$UpdateGitLabMergeRequest,
        [string]$ReleaseVersion,

        [ArgumentCompleter([RivetTagCompleter])]
        [string]$FromTag,

        [ArgumentCompleter([RivetBranchCompleter])]
        [string]$MergeTargetBranch = 'main',

        [switch]$IncludeCommitHash = $true,
        [switch]$IncludeAuthor = $true,
        [switch]$SyncGitLabMetadata,
        [switch]$DeleteMissingLabels,
        [switch]$Commit,

        [ArgumentCompleter([RivetCommitTypeCompleter])]
        [string]$CommitType,

        [ArgumentCompleter([RivetCommitScopeCompleter])]
        [string]$CommitScope,

        [string]$CommitDescription,

        [ArgumentCompleter([RivetCommitFilesCompleter])]
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
        [switch]$DryRun,
        [switch]$Raw
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    $moduleRoot = $PSScriptRoot
    if ([System.IO.Path]::GetFileName($moduleRoot) -ieq 'scripts') {
        $moduleRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($moduleRoot, '..'))
    }
    $scriptsRoot = [System.IO.Path]::Combine($moduleRoot, 'scripts')
    $runnerScript = [System.IO.Path]::Combine($moduleRoot, 'run.ps1')

    if ($Command -eq 'help' -or $Help -or $PSBoundParameters.ContainsKey('HelpParameter')) {
        $helpScript = [System.IO.Path]::Combine($moduleRoot, 'help.ps1')
        if (-not [string]::IsNullOrWhiteSpace($HelpParameter) -and $HelpParameter -ine 'help') {
            & $helpScript -Param $HelpParameter
        } else {
            & $helpScript
        }
        return
    }

    $repositoryProbe = if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) { (Get-Location).Path } else { $RepositoryRoot }
    $gitRoot = @(& git -C $repositoryProbe rev-parse --show-toplevel 2>$null)
    if ($LASTEXITCODE -ne 0 -or -not $gitRoot.Count) { throw 'rivet must run from inside a Git repository.' }
    $resolvedRepoRoot = [System.IO.Path]::GetFullPath(([string]$gitRoot[0]).Trim())
    $resolvedConfigPath = if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
        Resolve-RivetPath -RepositoryRoot $resolvedRepoRoot -ItemName 'repo_config.json'
    } else {
        [System.IO.Path]::GetFullPath($ConfigPath)
    }

    $profileConfig = if ([System.IO.File]::Exists($resolvedConfigPath)) { Get-RivetConfiguration -ConfigPath $resolvedConfigPath } else { $null }
    $repositoryProfile = Get-RivetProfile -Config $profileConfig
    if (($Profile -or $Manifest) -and -not ($Command -in @('init', 'bootstrap') -or $Init -or $Bootstrap)) {
        throw '-Profile and -Manifest are initialization options. Subsequent commands use repo_config.json.'
    }

    if ($Command -eq 'menu' -or $Menu) {
        Invoke-RivetMenu -RunnerPath $runnerScript -ConfigPath $resolvedConfigPath -RepositoryRoot $resolvedRepoRoot
        return
    }

    $asciiBanner = @'
   ┌───┐    █████  ████ ██   ██ ██████ ██████
  ╱▓▓▓▓▓╲   ██  ██  ██  ██   ██ ██      ██
 │▓█▓▓▓█▓│--█████   ██   ██ ██  █████    ██
  ╲▓▓▓▓▓╱   ██ ██   ██   ██ ██  ██        ██
   └─┼─┘    ██  ██ ████   ███   ██████   ██
     |      |    |  ||     ||    |  |    ||
     |      StaticCanvas repository command center
     |      Local by default; remote sync is opt-in
'@

    $reportRows = [System.Collections.Generic.List[object]]::new(7)
    $failure = $null
    $versionSummary = $null
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

    if (-not $Raw) {
        $bannerTokens = ConvertTo-AsciiTokens -Lines ($asciiBanner -split '\r?\n') -Connectivity 8
        foreach ($line in @(ConvertTo-GradientAsciiLines -TokenObject $bannerTokens -Mode Horizontal -StartColor @(0, 180, 255) -EndColor @(255, 60, 180))) {
            [Console]::WriteLine($line)
        }
        [Console]::WriteLine('')
    }

    if ($Command -in @('work-items', 'issues', 'sync-issues', 'workitem', 'template', 'tasks', 'tasklist', 'wi', 'view', 'close', 'reopen', 'generate-list') -or $WorkItems -or $SyncWorkItems -or $PullIssues -or $PushIssues -or $ListIssues -or $NewIssue -or $ViewIssue -or $CloseIssue -or $ReopenIssue -or $GenerateList) {
        $workAction = if ($ViewIssue -or $Command -eq 'view') { 'View' }
                      elseif ($CloseIssue -or $Command -eq 'close') { 'Close' }
                      elseif ($ReopenIssue -or $Command -eq 'reopen') { 'Reopen' }
                      elseif ($GenerateList -or $Command -in @('generate-list')) { 'GenerateList' }
                      elseif ($PullIssues) { 'Pull' }
                      elseif ($PushIssues) { 'Push' }
                      elseif ($NewIssue -or $Command -eq 'template' -or (-not [string]::IsNullOrWhiteSpace($IssueTitle) -and -not $ViewIssue -and -not $CloseIssue -and -not $ReopenIssue)) { 'New' }
                      elseif ($SyncWorkItems) { 'Push' }
                      else { 'List' }

        $workConfig = $null
        if ([System.IO.File]::Exists($resolvedConfigPath)) {
            try { $workConfig = Get-RivetConfiguration -ConfigPath $resolvedConfigPath } catch {}
        }
        $workResult = Sync-RivetWorkItems `
            -RepositoryRoot $resolvedRepoRoot `
            -Config $workConfig `
            -Action $workAction `
            -Iid $IssueIid `
            -Title $IssueTitle `
            -Description $IssueDescription `
            -Labels $IssueLabels `
            -State $IssueState `
            -Milestone $IssueMilestone `
            -ForceRefresh:$ForceRefresh `
            -DryRun:$DryRun `
            -Raw:$Raw
        return
    }

    if ($Command -eq 'init' -or $Init) {
        $null = Initialize-RivetRepository -RepositoryRoot $resolvedRepoRoot -Profile $Profile -Manifest $Manifest -ConfigPath $resolvedConfigPath -Bun:$Bun -DryRun:$DryRun -Confirm:$false
        return
    }

    if ($Command -eq 'bootstrap' -or $Bootstrap) {
        $null = Initialize-RivetRepository -RepositoryRoot $resolvedRepoRoot -Profile $Profile -Manifest $Manifest -ConfigPath $resolvedConfigPath -Bun:$Bun -DryRun:$DryRun -Confirm:$false
        if ($DryRun) {
            [Console]::WriteLine((Format-AnsiText -Text 'GitLab metadata synchronization will run after configuration is applied.' -Color @(145, 155, 175)))
            return
        }
        $syncScript = [System.IO.Path]::Combine($scriptsRoot, 'Sync-GitLabRepositoryMetadata.ps1')
        $null = & $syncScript -ConfigPath $resolvedConfigPath -Confirm:$false
        return
    }

    if ($Command -eq 'doctor' -or $Doctor) {
        $doctorResult = Test-RivetRepository -RepositoryRoot $resolvedRepoRoot -ConfigPath $resolvedConfigPath
        if (-not $doctorResult.Ready) { throw "rivet doctor found $(@($doctorResult.Failures).Count) failed check(s)." }
        return
    }

    if ($Command -eq 'status' -or $Status) {
        $null = Write-RivetRepositoryStatus -RepositoryRoot $resolvedRepoRoot -ConfigPath $resolvedConfigPath
        return
    }

    if ($Command -eq 'version' -or $VersionReport) {
        $null = Write-RivetVersionReport -RepositoryRoot $resolvedRepoRoot
        return
    }

    if ($Command -in @('flow', 'pipeline') -or $FlowGraph) {
        Show-RivetFlowGraph
        return
    }

    if ($Command -eq 'readme' -or $ValidateReadme) {
        $readmeResult = Test-ReadmeStructure -RepositoryRoot $resolvedRepoRoot -ConfigPath $resolvedConfigPath
        if (-not $readmeResult.Ready) { throw "README is missing $(@($readmeResult.Missing).Count) required heading(s)." }
        return
    }

    if ($Command -eq 'history' -or $Command -eq 'glo' -or $GitLog) {
        Write-PrettyGitLog -RepositoryRoot $resolvedRepoRoot -Count $GitLogCount -All:$GitLogAll -NoMerges:$GitLogNoMerges -Scope $CommitScope
        return
    }

    if ($Command -eq 'rebuild-changelog' -or $RebuildChangelog) {
        $RebuildChangelog = $true
        $UpdateReleaseDocs = $true
        if (-not $PSBoundParameters.ContainsKey('SkipVersion')) { $SkipVersion = $true }
        if (-not $PSBoundParameters.ContainsKey('SkipReadmeMetadata')) { $SkipReadmeMetadata = $true }
        if (-not $PSBoundParameters.ContainsKey('SkipTableOfContents')) { $SkipTableOfContents = $true }
        if (-not $PSBoundParameters.ContainsKey('SkipReadmeValidation')) { $SkipReadmeValidation = $true }
    }

    if ($Snapshot -and -not ($Tag -or $Command -eq 'tag')) { throw '-Snapshot requires -Tag.' }
    if ($TagForce -and -not ($Tag -or $Command -eq 'tag')) { throw '-TagForce requires -Tag.' }
    if (-not [string]::IsNullOrWhiteSpace($TagVersion) -and -not ($Tag -or $Command -eq 'tag')) { throw '-TagVersion requires -Tag.' }
    if ($CreateGitLabMergeRequest -and $UpdateGitLabMergeRequest) { throw '-CreateGitLabMergeRequest and -UpdateGitLabMergeRequest are mutually exclusive.' }
    if ($UpdateChangelogJson -and -not ($UpdateReleaseDocs -or $FinalizeRelease -or $PrepRelease -or $RebuildChangelog -or $Command -in @('prep-release', 'rebuild-changelog'))) { throw '-UpdateChangelogJson requires -UpdateReleaseDocs, -FinalizeRelease, -RebuildChangelog, or prep-release.' }

    if ($Command -eq 'tag' -or $Tag) {
        $tagParameters = @{
            RepositoryRoot = $resolvedRepoRoot
            ConfigPath     = $resolvedConfigPath
            Snapshot       = $Snapshot
            Force          = $TagForce
            DryRun         = $DryRun
        }
        if (-not [string]::IsNullOrWhiteSpace($TagVersion)) { $tagParameters.Version = $TagVersion }
        $null = Invoke-RepositoryTag @tagParameters
        return
    }

    if ($Command -eq 'commit' -or $Commit) {
        $Commit = $true
    }

    if ($Command -eq 'prep-release' -or $PrepRelease) {
        $PrepRelease = $true
        $FinalizeRelease = $true
        $UpdateMergeRequest = $true
        if ($Commit -and -not $CommitAll -and -not $CommitFiles) {
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
            $version = Get-ConventionalCommitVersion -RepositoryRoot $resolvedRepoRoot
            $null = @(& $repositoryProfile.UpdateVersion $resolvedRepoRoot $profileConfig $version.Version ([bool]$DryRun) *>&1)
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
            Write-LazyLog -Level act -Title 'HEADER' -Message 'Processing the README header using the repository profile.' -Log
            $null = @(& $repositoryProfile.UpdateHeader $resolvedRepoRoot $profileConfig $resolvedConfigPath ([bool]$DryRun) *>&1)
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
            $readmePath = [System.IO.Path]::Combine($resolvedRepoRoot, 'README.md')
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
            Write-LazyLog -Level act -Title 'README' -Message 'Validating configured README sections.' -Log
            $readmeResult = Test-ReadmeStructure -RepositoryRoot $resolvedRepoRoot -ConfigPath $resolvedConfigPath -Quiet
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

    if (-not ($UpdateReleaseDocs -or $FinalizeRelease -or $RebuildChangelog)) {
        Write-LazyLog -Level skip -Title 'RELEASE' -Message 'Release-document generation was not requested.' -Log
        Add-ReportRow -State 'SKIP' -Label 'RELEASE' -Detail 'release-document generation not requested'
    } else {
        try {
            $rangeMessage = if ($RebuildChangelog) {
                'Git tag history across all reachable releases'
            } elseif ($FromTag) {
                "the explicit $FromTag baseline"
            } else {
                'the latest reachable GitLab release tag'
            }
            $actionVerb = if ($RebuildChangelog) { 'Rebuilding complete changelog from' } else { 'Generating changelog and release notes from' }
            Write-LazyLog -Level act -Title 'RELEASE' -Message "$actionVerb $rangeMessage." -Log
            $releaseParameters = @{
                RepositoryRoot     = $resolvedRepoRoot
                ConfigPath         = $resolvedConfigPath
                Finalize           = $FinalizeRelease
                Rebuild            = $RebuildChangelog
                IncludeCommitHash  = $IncludeCommitHash
                IncludeAuthor      = $IncludeAuthor
                WriteChangelogJson = $UpdateChangelogJson
                DryRun             = $DryRun
            }
            if (-not [string]::IsNullOrWhiteSpace($FromTag)) { $releaseParameters.FromTag = $FromTag }
            if (-not [string]::IsNullOrWhiteSpace($ReleaseVersion)) { $releaseParameters.Version = $ReleaseVersion }
            elseif (-not $SkipVersion) { $releaseParameters.Version = $version.Version }
            if (-not [string]::IsNullOrWhiteSpace($CommitScope)) { $releaseParameters.Scope = $CommitScope }
            $null = @(Update-ReleaseDocumentation @releaseParameters *>&1)
            $modeDetail = if ($DryRun -and $RebuildChangelog) {
                'complete changelog previewed'
            } elseif ($RebuildChangelog) {
                'complete changelog rebuilt across all tags'
            } elseif ($DryRun) {
                'release documentation previewed'
            } elseif ($FinalizeRelease) {
                'release documentation finalized'
            } else {
                'draft release documentation synchronized'
            }
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
                RepositoryRoot    = $resolvedRepoRoot
                ConfigPath        = $resolvedConfigPath
                TargetBranch      = $MergeTargetBranch
                IncludeCommitHash = $IncludeCommitHash
                IncludeAuthor     = $IncludeAuthor
                DryRun            = $DryRun
            }
            if (-not [string]::IsNullOrWhiteSpace($FromTag)) { $mergeRequestParameters.FromTag = $FromTag }
            if (-not [string]::IsNullOrWhiteSpace($ReleaseVersion)) { $mergeRequestParameters.Version = $ReleaseVersion }
            elseif (-not $SkipVersion) { $mergeRequestParameters.Version = $version.Version }
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
            $remoteResult = Invoke-GitLabMergeRequest -RepositoryRoot $resolvedRepoRoot -ConfigPath $resolvedConfigPath -Mode $remoteMergeRequestMode -DryRun:$DryRun
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
                RepositoryRoot = $resolvedRepoRoot
                ConfigPath     = $resolvedConfigPath
                DryRun         = $DryRun
            }
            if (-not [string]::IsNullOrWhiteSpace($CommitType)) { $commitParameters.Type = $CommitType }
            if (-not [string]::IsNullOrWhiteSpace($CommitScope)) { $commitParameters.Scope = $CommitScope }
            if (-not [string]::IsNullOrWhiteSpace($CommitDescription)) { $commitParameters.Description = $CommitDescription }
            if ($prepReleaseDefaultCommitSelection) {
                $releaseFileSet = [System.Collections.Generic.HashSet[string]]::new([string[]](@('CHANGELOG.md', 'release-notes.md', 'docs/data/changelog.json', 'README.md') + @(& $repositoryProfile.ReleaseFiles $resolvedRepoRoot $profileConfig)), [System.StringComparer]::Ordinal)
                $changedReleaseFiles = @(& git -C $resolvedRepoRoot status --porcelain=v1 --untracked-files=all) | ForEach-Object {
                    if ($_.Length -gt 3) { $_.Substring(3).Trim('"') }
                } | Where-Object { $releaseFileSet.Contains($_) }
                if (-not @($changedReleaseFiles).Count) { throw 'Prep Release did not produce any tracked release-file changes to commit.' }
                $commitParameters.Files = @($changedReleaseFiles)
            } elseif ($CommitFiles) { $commitParameters.Files = $CommitFiles }
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

    $reportRowsConverted = @($reportRows | ForEach-Object {
        @{ State = $_.State; Label = $_.Label; Detail = $_.Detail }
    })

    $projName = (Split-Path $resolvedRepoRoot -Leaf)
    if ([System.IO.File]::Exists($resolvedConfigPath)) {
        try {
            $cfg = Get-RivetConfiguration -ConfigPath $resolvedConfigPath
            $projName = $cfg.project.displayName
        } catch {}
    }

    $headSha = try { (& git -C $resolvedRepoRoot rev-parse --short HEAD 2>$null).Trim() } catch { '' }
    $branchName = try { (& git -C $resolvedRepoRoot branch --show-current 2>$null).Trim() } catch { '' }
    $upstreamStatus = try { (& git -C $resolvedRepoRoot status -sb 2>$null | Select-Object -First 1).TrimStart('#').Trim() } catch { '' }

    $resolvedVersion = if ($versionSummary) { $versionSummary.ResolvedVersion } else { '' }

    $reportResult = Write-RivetReportCard `
        -Title 'RIVET AUTOMATION REPORT' `
        -Mode $mode `
        -Elapsed $stopwatch.Elapsed `
        -ProjectName $projName `
        -Version $resolvedVersion `
        -Branch $branchName `
        -Head $headSha `
        -Upstream $upstreamStatus `
        -Rows $reportRowsConverted `
        -Artifacts @() `
        -Raw:$Raw

    if ($null -ne $failure) {
        throw $failure
    }

    if ($Raw) {
        return $reportResult
    }
}
