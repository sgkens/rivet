<#
.SYNOPSIS
    Opens the reusable rivet workflow menu.
.DESCRIPTION
    Builds reviewed run.ps1 invocations for local metadata, release documents,
    merge requests, GitLab metadata, Conventional Commits, Git history, and
    help. Workflow defaults avoid unrelated writes and destructive choices.
.PARAMETER RunnerPath
    Absolute or relative path to the rivet run.ps1 entry point.
.PARAMETER ConfigPath
    Path to repo_config.json used for the project display name.
.PARAMETER RepositoryRoot
    Consuming repository operated on by reviewed runner commands.
.EXAMPLE
    Invoke-RivetMenu -RunnerPath ./rivet/run.ps1 -ConfigPath ./repo_config.json -RepositoryRoot ./
#>
function Invoke-RivetMenu {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RunnerPath,
        [Parameter(Mandatory)][string]$ConfigPath,
        [Parameter(Mandatory)][string]$RepositoryRoot
    )

    if ([Console]::IsInputRedirected -or [Console]::IsOutputRedirected) {
        throw 'The rivet menu requires an interactive terminal. Use run.ps1 help for non-interactive usage.'
    }
    $resolvedRunner = [System.IO.Path]::GetFullPath($RunnerPath)
    if (-not [System.IO.File]::Exists($resolvedRunner)) { throw "Runner not found: $resolvedRunner" }
    $projectName = 'repository'
    $packageName = 'package'
    $packageVersion = 'unversioned'
    if ([System.IO.File]::Exists($ConfigPath)) {
        $menuConfig = [System.IO.File]::ReadAllText($ConfigPath) | ConvertFrom-Json
        if ($null -ne $menuConfig.project -and -not [string]::IsNullOrWhiteSpace([string]$menuConfig.project.displayName)) {
            $projectName = [string]$menuConfig.project.displayName
        }
    }
    $repositoryRoot = [System.IO.Path]::GetFullPath($RepositoryRoot)
    $packagePath = [System.IO.Path]::Combine($repositoryRoot, 'package.json')
    if ([System.IO.File]::Exists($packagePath)) {
        $packageDocument = [System.Text.Json.JsonDocument]::Parse([System.IO.File]::ReadAllText($packagePath))
        try {
            $packageName = $packageDocument.RootElement.GetProperty('name').GetString()
            $packageVersion = $packageDocument.RootElement.GetProperty('version').GetString()
        } finally { $packageDocument.Dispose() }
    }

    function New-MenuItem([string]$Label, [object]$Value, [string]$Description = '', [switch]$MultiAction) {
        [pscustomobject]@{
            Label = $Label
            Value = $Value
            Description = $Description
            MultiAction = [bool]$MultiAction
        }
    }

    function Select-MenuValue {
        param([string]$Title, [object[]]$Items, [int]$DefaultIndex = 0)
        Show-SMenu -Title $Title -Items $Items -DefaultIndex $DefaultIndex
    }

    function Select-YesNo {
        param([string]$Title, [bool]$Default = $false)
        $items = if ($Default) {
            @(
                (New-MenuItem 'Yes' $true 'Confirm and enable this option for the workflow.')
                (New-MenuItem 'No' $false 'Skip and proceed with this option disabled.')
            )
        } else {
            @(
                (New-MenuItem 'No' $false 'Skip and proceed with this option disabled.')
                (New-MenuItem 'Yes' $true 'Confirm and enable this option for the workflow.')
            )
        }
        return Select-MenuValue -Title $Title -Items $items
    }

    function Read-OptionalValue([string]$Label, [string]$Default = '') {
        [Console]::WriteLine('')
        $promptLabel = Format-AnsiText -Text "▶ $Label" -Color @(0, 200, 255) -Bold
        $defaultHint = if ([string]::IsNullOrWhiteSpace($Default)) {
            Format-AnsiText -Text ' (optional, press enter to skip)' -Color @(145, 155, 175)
        } else {
            Format-AnsiText -Text " (default: $Default, press enter to accept)" -Color @(145, 155, 175)
        }
        [Console]::WriteLine("$promptLabel$defaultHint")
        $value = Read-Host -Prompt '  > '
        [Console]::WriteLine('')
        if ([string]::IsNullOrWhiteSpace($value)) { return $Default }
        return $value.Trim()
    }

    function Add-IsolatedActionDefaults([System.Collections.IDictionary]$Parameters) {
        $Parameters.SkipVersion = $true
        $Parameters.SkipReadmeMetadata = $true
        $Parameters.SkipTableOfContents = $true
        $Parameters.SkipReadmeValidation = $true
    }

    function Format-RunnerCommand([System.Collections.IDictionary]$Parameters) {
        $parts = [System.Collections.Generic.List[string]]::new()
        $parts.Add('./rivet.ps1')
        foreach ($key in $Parameters.Keys) {
            $value = $Parameters[$key]
            if ($value -is [bool]) {
                if ($value) { $parts.Add("-$key") } else { $parts.Add("-${key}:`$false") }
            } else {
                $escaped = ([string]$value).Replace("'", "''")
                $parts.Add("-$key '$escaped'")
            }
        }
        return $parts -join ' '
    }

    function Invoke-ReviewedWorkflow {
        param([string]$Title, [System.Collections.IDictionary]$Parameters)
        $reviewWidth = [Math]::Max(30, [Math]::Min(132, ([Console]::WindowWidth - 2)))
        $reviewContentWidth = [Math]::Max(20, $reviewWidth - 6)
        $commandLines = @(Split-SMenuText -Text (Format-RunnerCommand $Parameters) -Width $reviewContentWidth)
        $reviewLines = [System.Collections.Generic.List[string]]::new()
        $reviewLines.Add((Format-AnsiText -Text $Title -Color @(220, 225, 235) -Bold))
        $reviewLines.Add('')
        $reviewLines.Add((Format-AnsiText -Text 'COMMAND' -Color @(145, 155, 175) -Bold))
        foreach ($commandLine in $commandLines) {
            $reviewLines.Add((Format-AnsiText -Text $commandLine -Color @(80, 220, 150)))
        }
        [Console]::Clear()
        [Console]::WriteLine((New-TuiPanel -Content $reviewLines.ToArray() -Title 'COMMAND REVIEW' -Width $reviewWidth -BorderStyle Rounded -ColorPalette @{ Border = @(48, 58, 78); Title = @(0, 210, 255) }))
        [Console]::WriteLine('')
        $runChoice = Select-MenuValue -Title 'RUN THIS WORKFLOW?' -Items @(
            (New-MenuItem 'Run command' 'run' 'Execute the reviewed command line arguments immediately and stream live execution output.')
            (New-MenuItem 'Back' 'back' 'Cancel execution and return to the previous workflow menu without applying changes.')
        )
        if ($runChoice -ne 'run') { return }
        [Console]::Clear()
        $workflowTimer = [System.Diagnostics.Stopwatch]::StartNew()
        $workflowState = 'COMPLETE'
        $isHelpWorkflow = $Parameters.Contains('Help') -and [bool]$Parameters.Help
        $argList = [System.Collections.Generic.List[string]]::new()
        $argList.Add('-RepositoryRoot')
        $argList.Add($repositoryRoot)
        foreach ($key in $Parameters.Keys) {
            $value = $Parameters[$key]
            if ($value -is [bool]) {
                if ($value) {
                    $argList.Add("-$key")
                } else {
                    $argList.Add("-${key}:`$false")
                }
            } elseif ($value -is [System.Collections.IEnumerable] -and -not ($value -is [string])) {
                $arrayItems = @($value | ForEach-Object { [string]$_ })
                if ($arrayItems.Count -gt 0) {
                    $argList.Add("-$key")
                    $argList.Add(($arrayItems -join ','))
                }
            } else {
                $argList.Add("-$key")
                $argList.Add([string]$value)
            }
        }

        $isInteractive = (
            ($Parameters.Contains('Commit') -and [bool]$Parameters.Commit -and -not ($Parameters.Contains('DryRun') -and [bool]$Parameters.DryRun)) -or
            ($Parameters.Contains('Tag') -and [bool]$Parameters.Tag -and -not ($Parameters.Contains('DryRun') -and [bool]$Parameters.DryRun))
        )
        $workflowOutput = @()
        $prevColor = $env:FORCE_COLOR
        try {
            # Keep workflow module imports outside the active TUI process.
            # Re-importing Rivet while this function runs invalidates its local
            # menu functions when control returns from the workflow.
            $env:FORCE_COLOR = '1'
            if ($isInteractive) {
                & pwsh -NoLogo -NoProfile -File $resolvedRunner @argList
            } else {
                $workflowOutput = @(& pwsh -NoLogo -NoProfile -File $resolvedRunner @argList 2>&1 | ForEach-Object { [string]$_ })
            }
            if ($LASTEXITCODE -ne 0) {
                throw "Rivet workflow exited with code $LASTEXITCODE."
            }
        } catch {
            $workflowState = 'FAILED'
            $workflowOutput += (Format-AnsiText -Text "FAILED  $($_.Exception.Message)" -Color @(255, 90, 105) -Bold)
        } finally {
            $env:FORCE_COLOR = $prevColor
            $workflowTimer.Stop()
        }

        if ($isHelpWorkflow -and $workflowState -eq 'COMPLETE') {
            Show-RivetPager -Title 'RIVET HELP' -Lines ([string[]]$workflowOutput)
            return
        }

        if ($isInteractive) {
            [Console]::WriteLine('')
            $elapsed = Get-ElapsedTime -TimeSpan $workflowTimer.Elapsed
            $resultColor = if ($workflowState -eq 'COMPLETE') { @(80, 220, 150) } else { @(255, 90, 105) }
            $resultLines = @(
                (Format-AnsiText -Text "$workflowState  $elapsed" -Color $resultColor -Bold)
                (Format-AnsiText -Text 'Press [Esc] or [q] to return to the command center.' -Color @(145, 155, 175))
            )
            $resultWidth = [Math]::Max(30, [Math]::Min(132, ([Console]::WindowWidth - 2)))
            [Console]::WriteLine((New-TuiPanel -Content $resultLines -Title 'WORKFLOW RESULT' -Width $resultWidth -BorderStyle Rounded -ColorPalette @{ Border = @(48, 58, 78); Title = $resultColor }))

            while ($true) {
                $k = [Console]::ReadKey($true)
                if ($k.Key -eq 'Escape') {
                    [System.Threading.Thread]::Sleep(15)
                    if ([Console]::KeyAvailable) {
                        while ([Console]::KeyAvailable) { $null = [Console]::ReadKey($true) }
                        continue
                    }
                    break
                }
                if ($k.Key -in @('Enter', 'LeftArrow') -or $k.KeyChar -in @('q', 'Q', 'h', 'H', ' ')) {
                    break
                }
            }
            return
        }

        # Check if output exceeds terminal viewport height
        $windowHeight = try { [Console]::WindowHeight } catch { 24 }
        $threshold = [Math]::Max(8, $windowHeight - 6)
        if ($workflowOutput.Count -gt $threshold) {
            Show-RivetPager -Title $Title.ToUpper() -Lines ([string[]]$workflowOutput)
            return
        }

        # Output fits cleanly in current viewport
        [Console]::Clear()
        foreach ($line in $workflowOutput) {
            [Console]::WriteLine($line)
        }

        [Console]::WriteLine('')
        $elapsed = Get-ElapsedTime -TimeSpan $workflowTimer.Elapsed
        $resultColor = if ($workflowState -eq 'COMPLETE') { @(80, 220, 150) } else { @(255, 90, 105) }
        $resultLines = @(
            (Format-AnsiText -Text "$workflowState  $elapsed" -Color $resultColor -Bold)
            (Format-AnsiText -Text 'Press [Esc] or [q] to return to the command center.' -Color @(145, 155, 175))
        )
        $resultWidth = [Math]::Max(30, [Math]::Min(132, ([Console]::WindowWidth - 2)))
        [Console]::WriteLine((New-TuiPanel -Content $resultLines -Title 'WORKFLOW RESULT' -Width $resultWidth -BorderStyle Rounded -ColorPalette @{ Border = @(48, 58, 78); Title = $resultColor }))

        while ($true) {
            $k = [Console]::ReadKey($true)
            if ($k.Key -eq 'Escape') {
                [System.Threading.Thread]::Sleep(15)
                if ([Console]::KeyAvailable) {
                    while ([Console]::KeyAvailable) { $null = [Console]::ReadKey($true) }
                    continue
                }
                break
            }
            if ($k.Key -in @('Enter', 'LeftArrow') -or $k.KeyChar -in @('q', 'Q', 'h', 'H', ' ')) {
                break
            }
        }
    }

    function Select-PreviewMode([System.Collections.IDictionary]$Parameters) {
        $mode = Select-MenuValue -Title 'EXECUTION MODE' -Items @(
            (New-MenuItem 'Preview only' 'preview' 'Performs a non-destructive dry-run simulation without writing file changes or publishing remote updates.')
            (New-MenuItem 'Apply changes' 'apply' 'Applies all calculated changes directly to repository files, manifests, and remote targets.')
        )
        if ($null -eq $mode) { return $false }
        if ($mode -eq 'preview') { $Parameters.DryRun = $true }
        return $true
    }

    function Add-DocumentOptions([System.Collections.IDictionary]$Parameters) {
        $fromTag = Read-OptionalValue 'Baseline Git ref'
        if ($fromTag) { $Parameters.FromTag = $fromTag }
        $version = Read-OptionalValue 'Release version override'
        if ($version) { $Parameters.ReleaseVersion = $version }
        $scope = Read-OptionalValue 'Exact Conventional Commit scope; blank includes all'
        if ($scope) { $Parameters.CommitScope = $scope }
        $includeHash = Select-YesNo -Title 'INCLUDE COMMIT HASHES?' -Default $true
        if ($null -eq $includeHash) { return $false }
        if (-not $includeHash) { $Parameters.IncludeCommitHash = $false }
        $includeAuthor = Select-YesNo -Title 'INCLUDE COMMIT AUTHORS?' -Default $true
        if ($null -eq $includeAuthor) { return $false }
        if (-not $includeAuthor) { $Parameters.IncludeAuthor = $false }
        return $true
    }

    function Add-ChangelogJsonOption([System.Collections.IDictionary]$Parameters) {
        $docsDataPath = [System.IO.Path]::Combine($repositoryRoot, 'docs', 'data')
        $generateJson = Select-YesNo -Title 'GENERATE CURATED DOCS CHANGELOG JSON?' -Default ([System.IO.Directory]::Exists($docsDataPath))
        if ($null -eq $generateJson) { return $false }
        if ($generateJson) { $Parameters.UpdateChangelogJson = $true }
        return $true
    }

    $mainItems = @(
        (New-MenuItem 'Initialize repository' 'init' 'Scaffolds repository configuration (repo_config.json, repo_meta.json, toolchain configs). Supports standard npm/Node or Bun-native templates with optional remote GitLab metadata synchronization.' -MultiAction)
        (New-MenuItem 'Prep Release' 'prep_release' 'Orchestrates full release preparation: calculates next SemVer from Conventional Commits, updates package manifests (package.json & jsr.jsonc), generates CHANGELOG.md, release-notes.md, README badges, and mr.md.' -MultiAction)
        (New-MenuItem 'Local metadata' 'local' 'Updates repository-local metadata files without modifying Git history. Manages SemVer manifest versions, centered README badges & titles, and collapsible table-of-contents.' -MultiAction)
        (New-MenuItem 'Release documents' 'release' 'Generates and manages release notes. Creates draft notes under [Unreleased], finalizes dated release sections (## [x.y.z]), or rebuilds full changelog across all historical Git tags.')
        (New-MenuItem 'Merge request' 'merge_request' 'Generates the managed mr.md document from commit history and offers direct publication or updates to GitLab Merge Requests via REST API.' -MultiAction)
        (New-MenuItem 'GitLab metadata' 'gitlab' 'Synchronizes project descriptions, topics, and managed label taxonomy from repo_meta.json directly to the GitLab project via REST API.')
        (New-MenuItem 'Conventional Commit' 'commit' 'Interactive commit assistant. Guides through type, scope, breaking changes, and description according to Conventional Commits standards with full patch diff review.' -MultiAction)
        (New-MenuItem 'Work items & tasks' 'work_items' 'Bidirectional GitLab issue tracker and local task management. Supports markdown work items (.rivet/work-items/*.md), table metadata, criteria checklists, and pull/push synchronization.' -MultiAction)
        (New-MenuItem 'Tag and publish' 'tag' 'Creates and pushes SemVer Git tags to remote. Supports snapshot tags for CI validation or production release tags (vX.Y.Z-release) that trigger automated package publication.')
        (New-MenuItem 'Git history' 'history' 'Renders an enriched terminal git log graph displaying commit hashes, author attribution, relative timestamps, file change statistics, and GPG signature status.')
        (New-MenuItem 'Repository status' 'status' 'Displays complete repository status: branch, HEAD commit, upstream tracking, dirty worktree status, current SemVer baseline, and next release tag projection.')
        (New-MenuItem 'Version report' 'version_report' 'Explains Conventional Commit version resolution: scans commit log from baseline tag, breaks down breaking/feature/fix changes, and projects next SemVer.')
        (New-MenuItem 'Doctor' 'doctor' 'Performs comprehensive health diagnostics across PowerShell, Git, Node/Bun runtimes, configuration schemas, manifest version parity, required files, and API tokens.')
        (New-MenuItem 'Pipeline flow graph' 'flow' 'Renders an interactive ASCII ANSI diagram illustrating Rivet complete automation lifecycle from worktree discovery to GitLab release publication.')
        (New-MenuItem 'Help' 'help' 'Opens interactive documentation and command manual covering all CLI switches, configuration properties, submodules, and workflow patterns.')
        (New-MenuItem 'Exit' 'exit' 'Closes the Rivet interactive command center and returns to shell prompt.')
    )

    Enable-TerminalAltBuffer
    try {
    while ($true) {
        [Console]::Clear()
        $action = Select-MenuValue -Title "RIVET  SELECT WORKFLOW  $projectName  $packageName v$packageVersion" -Items $mainItems
        if ($null -eq $action -or $action -eq 'exit') { return }

        switch ($action) {
            'init' {
                $kind = Select-MenuValue -Title 'INITIALIZE REPOSITORY' -Items @(
                    (New-MenuItem 'Local configuration' 'local' 'Creates repo_config.json, repo_meta.json, vite config, and standard lint/test toolchain configuration files locally without connecting to remote APIs.')
                    (New-MenuItem 'Local configuration (Bun)' 'local_bun' 'Creates local repository files plus Bun-native configuration files (bunfig.toml and bun.lock) configured for Bun package manifests.')
                    (New-MenuItem 'Configuration and GitLab' 'gitlab' 'Scaffolds all local repository files and immediately synchronizes project descriptions, repository topics, and issue labels to GitLab.' -MultiAction)
                    (New-MenuItem 'Configuration and GitLab (Bun)' 'gitlab_bun' 'Full Bun-native repository setup combined with automatic remote GitLab project metadata and label catalog synchronization.' -MultiAction)
                )
                if ($null -eq $kind) { continue }
                $isBun = $kind -in @('local_bun', 'gitlab_bun')
                $isGitlab = $kind -in @('gitlab', 'gitlab_bun')
                $p = if ($isGitlab) { [ordered]@{ Bootstrap = $true } } else { [ordered]@{ Init = $true } }
                if ($isBun) { $p.Bun = $true }
                if (-not (Select-PreviewMode $p)) { continue }
                $titleText = if ($isGitlab) {
                    if ($isBun) { 'Initialize Bun repository and GitLab metadata' } else { 'Initialize repository and GitLab metadata' }
                } else {
                    if ($isBun) { 'Initialize Bun repository configuration' } else { 'Initialize repository configuration' }
                }
                Invoke-ReviewedWorkflow -Title $titleText -Parameters $p
            }
            'prep_release' {
                $kind = Select-MenuValue -Title 'PREP RELEASE' -Items @(
                    (New-MenuItem 'Preview release preparation' 'preview' 'Performs a non-destructive dry-run. Simulates SemVer bump, previews package.json/jsr.jsonc updates, CHANGELOG.md, release notes, README header, and mr.md without disk writes.' -MultiAction)
                    (New-MenuItem 'Apply release preparation' 'apply' 'Applies full release preparation: calculates next version from Conventional Commits, updates manifest files, appends dated release notes to CHANGELOG.md, and rebuilds mr.md.' -MultiAction)
                    (New-MenuItem 'Apply and commit' 'commit' 'Applies full release preparation and immediately stages and commits an automated chore(release): prepare release metadata commit.' -MultiAction)
                )
                if ($null -eq $kind) { continue }
                $p = [ordered]@{ PrepRelease = $true }
                if (-not (Add-DocumentOptions $p)) { continue }
                if (-not (Add-ChangelogJsonOption $p)) { continue }
                if ($kind -eq 'preview') { $p.DryRun = $true }
                if ($kind -eq 'commit') { $p.Commit = $true; $p.CommitType = 'chore'; $p.CommitScope = 'release'; $p.CommitDescription = 'prepare release metadata' }
                Invoke-ReviewedWorkflow -Title 'Prepare release' -Parameters $p
            }
            'local' {
                $choice = Select-MenuValue -Title 'LOCAL METADATA' -Items @(
                    (New-MenuItem 'Preview all' 'preview_all' 'Simulates version calculation, centered README header generation, and table-of-contents insertion without making disk modifications.' -MultiAction)
                    (New-MenuItem 'Apply all' 'apply_all' 'Synchronizes calculated SemVer in package.json & jsr.jsonc, updates centered README badge header, and inserts dynamic TOC into README.md.' -MultiAction)
                    (New-MenuItem 'Version only' 'version' 'Calculates and writes SemVer bump strictly to package.json and jsr.jsonc without touching README headers or TOC.')
                    (New-MenuItem 'README header only' 'header' 'Regenerates the centered README banner, package title, description, and status/coverage badge table from repo_config.json.')
                    (New-MenuItem 'README TOC only' 'toc' 'Scans README.md heading hierarchy (H2-H4) and updates the collapsible table-of-contents marker block in-place.')
                    (New-MenuItem 'Validate README' 'validate_readme' 'Audits README.md against mandatory required section headings defined in repository configuration rules.')
                )
                if ($null -eq $choice) { continue }
                $p = [ordered]@{}
                switch ($choice) {
                    'preview_all' { $p.DryRun = $true }
                    'version' { $p.SkipReadmeMetadata = $true; $p.SkipTableOfContents = $true }
                    'header' { $p.SkipVersion = $true; $p.SkipTableOfContents = $true }
                    'toc' { $p.SkipVersion = $true; $p.SkipReadmeMetadata = $true }
                    'validate_readme' { $p = [ordered]@{ ValidateReadme = $true } }
                }
                Invoke-ReviewedWorkflow -Title 'Local repository metadata' -Parameters $p
            }
            'release' {
                $kind = Select-MenuValue -Title 'RELEASE DOCUMENTS' -Items @(
                    (New-MenuItem 'Generate draft' 'draft' 'Extracts Conventional Commits since the baseline Git tag and updates the ## [Unreleased] section in CHANGELOG.md and release-notes.md.')
                    (New-MenuItem 'Finalize release' 'finalize' 'Promotes the unreleased draft into a permanent, dated release section (## [x.y.z]) with author attribution and commit links.')
                    (New-MenuItem 'Rebuild changelog' 'rebuild' 'Scans all reachable historical Git tags in reverse chronological order and completely regenerates the full CHANGELOG.md and curated docs/data/changelog.json.' -MultiAction)
                )
                if ($null -eq $kind) { continue }
                $p = [ordered]@{}
                Add-IsolatedActionDefaults $p
                if ($kind -eq 'finalize') {
                    $p.FinalizeRelease = $true
                } elseif ($kind -eq 'rebuild') {
                    $p.RebuildChangelog = $true
                } else {
                    $p.UpdateReleaseDocs = $true
                }
                if ($kind -ne 'rebuild') {
                    if (-not (Add-DocumentOptions $p)) { continue }
                } else {
                    $scope = Read-OptionalValue 'Exact Conventional Commit scope; blank includes all'
                    if ($scope) { $p.CommitScope = $scope }
                    $includeHash = Select-YesNo -Title 'INCLUDE COMMIT HASHES?' -Default $true
                    if ($null -eq $includeHash) { continue }
                    if (-not $includeHash) { $p.IncludeCommitHash = $false }
                    $includeAuthor = Select-YesNo -Title 'INCLUDE COMMIT AUTHORS?' -Default $true
                    if ($null -eq $includeAuthor) { continue }
                    if (-not $includeAuthor) { $p.IncludeAuthor = $false }
                }
                if (-not (Add-ChangelogJsonOption $p)) { continue }
                if (-not (Select-PreviewMode $p)) { continue }
                $workflowTitle = if ($kind -eq 'rebuild') { 'Rebuild complete changelog' } else { 'Release documentation' }
                Invoke-ReviewedWorkflow -Title $workflowTitle -Parameters $p
            }
            'merge_request' {
                $kind = Select-MenuValue -Title 'MERGE REQUEST' -Items @(
                    (New-MenuItem 'Generate mr.md' 'document' 'Extracts conventional changes and metadata into the local mr.md document for review before GitLab submission.')
                    (New-MenuItem 'Generate and create on GitLab' 'create' 'Builds mr.md from commit history and immediately publishes a new GitLab Merge Request via REST API to the target branch.' -MultiAction)
                    (New-MenuItem 'Generate and update on GitLab' 'update' 'Builds mr.md and updates the existing open Merge Request for the current branch on GitLab with latest description and tasks.' -MultiAction)
                )
                if ($null -eq $kind) { continue }
                $p = [ordered]@{}
                Add-IsolatedActionDefaults $p
                $p.UpdateMergeRequest = $true
                if ($kind -eq 'create') { $p.CreateGitLabMergeRequest = $true }
                if ($kind -eq 'update') { $p.UpdateGitLabMergeRequest = $true }
                $target = Read-OptionalValue 'Target branch' 'main'
                if ($target) { $p.MergeTargetBranch = $target }
                if (-not (Add-DocumentOptions $p)) { continue }
                if (-not (Select-PreviewMode $p)) { continue }
                Invoke-ReviewedWorkflow -Title $(if ($kind -eq 'document') { 'Merge-request document' } else { "Merge-request document and GitLab $kind" }) -Parameters $p
            }
            'gitlab' {
                $p = [ordered]@{}
                Add-IsolatedActionDefaults $p
                $p.SyncGitLabMetadata = $true
                $delete = Select-YesNo -Title 'DELETE REMOTE LABELS MISSING FROM CONFIG?' -Default $false
                if ($null -eq $delete) { continue }
                if ($delete) { $p.DeleteMissingLabels = $true }
                if (-not (Select-PreviewMode $p)) { continue }
                Invoke-ReviewedWorkflow -Title 'GitLab project metadata' -Parameters $p
            }
            'commit' {
                $kind = Select-MenuValue -Title 'COMMIT WORKFLOW' -Items @(
                    (New-MenuItem 'Commit current changes' 'current' 'Interactive Conventional Commit tool. Reviews git diff, prompts for commit type, scope, breaking changes, and subject description, then commits staged files.')
                    (New-MenuItem 'Metadata and commit' 'metadata' 'Runs automated local metadata sync (version, header, TOC) first, then enters interactive Conventional Commit review.' -MultiAction)
                    (New-MenuItem 'Preview commit' 'preview' 'Dry-run mode. Previews the commit message, type, scope, and staged file list without executing git commit.')
                )
                if ($null -eq $kind) { continue }
                $p = [ordered]@{ Commit = $true }
                if ($kind -ne 'metadata') { Add-IsolatedActionDefaults $p }
                if ($kind -eq 'preview') { $p.DryRun = $true }
                Invoke-ReviewedWorkflow -Title 'Conventional Commit' -Parameters $p
            }
            'tag' {
                $kind = Select-MenuValue -Title 'TAG AND PUBLISH' -Items @(
                    (New-MenuItem 'Snapshot tag' 'snapshot' 'Validates clean worktree and pushes a plain SemVer tag (e.g. v1.2.0) to origin for CI test and lint validation without triggering publication.')
                    (New-MenuItem 'Production tag' 'production' 'Validates clean worktree, verifies manifest versions match, and creates a production release tag (v1.2.0-release) to trigger automated package publication.')
                )
                if ($null -eq $kind) { continue }
                $p = [ordered]@{ Tag = $true }
                if ($kind -eq 'snapshot') { $p.Snapshot = $true }
                $version = Read-OptionalValue 'Version override; blank calculates from commits'
                if ($version) { $p.TagVersion = $version }
                if (-not (Select-PreviewMode $p)) { continue }
                Invoke-ReviewedWorkflow -Title $(if ($kind -eq 'snapshot') { 'Snapshot tag' } else { 'Production publishing tag' }) -Parameters $p
            }
            'history' {
                $p = [ordered]@{ GitLog = $true }
                $countText = Read-OptionalValue 'Commit count' '25'
                $count = 0
                if (-not [int]::TryParse($countText, [ref]$count) -or $count -lt 1 -or $count -gt 500) {
                    [Console]::WriteLine((Format-AnsiText -Text 'Commit count must be between 1 and 500.' -Color @(255, 90, 105) -Bold))
                    $null = [Console]::ReadKey($true)
                    continue
                }
                $p.GitLogCount = $count
                $all = Select-YesNo -Title 'INCLUDE ALL LOCAL AND REMOTE REFS?' -Default $false
                if ($null -eq $all) { continue }
                if ($all) { $p.GitLogAll = $true }
                $noMerges = Select-YesNo -Title 'OMIT MERGE COMMITS?' -Default $false
                if ($null -eq $noMerges) { continue }
                if ($noMerges) { $p.GitLogNoMerges = $true }
                $scope = Read-OptionalValue 'Exact Conventional Commit scope; blank includes all'
                if ($scope) { $p.CommitScope = $scope }
                Invoke-ReviewedWorkflow -Title 'Detailed Git history' -Parameters $p
            }
            'status' { Invoke-ReviewedWorkflow -Title 'Repository status' -Parameters ([ordered]@{ Status = $true }) }
            'version_report' { Invoke-ReviewedWorkflow -Title 'Version explanation' -Parameters ([ordered]@{ VersionReport = $true }) }
            'doctor' { Invoke-ReviewedWorkflow -Title 'Repository diagnostics' -Parameters ([ordered]@{ Doctor = $true }) }
            'flow' { Invoke-ReviewedWorkflow -Title 'Pipeline flow graph' -Parameters ([ordered]@{ FlowGraph = $true }) }
            'work_items' {
                $taskAction = Select-MenuValue -Title 'WORK ITEMS & TASK MANAGEMENT' -Items @(
                    (New-MenuItem 'List tasks' 'list' 'Renders a styled ASCII table displaying all local work items (.rivet/work-items/*.md), showing issue IIDs, titles, milestones, labels, and sync states.')
                    (New-MenuItem 'View task details' 'view' 'Opens full details of a specific local work item, including metadata table, description, acceptance criteria, and discussion notes.')
                    (New-MenuItem 'Scaffold new work item' 'new' 'Scaffolds a new local work item markdown file formatted with standard table metadata and criteria checklist.')
                    (New-MenuItem 'Close task' 'close' 'Marks a local work item as closed, sets its sync state to push, and updates the aggregated work items list dashboard.')
                    (New-MenuItem 'Reopen task' 'reopen' 'Reopens a previously closed local work item, sets sync state to push, and updates the aggregated dashboard.')
                    (New-MenuItem 'Pull from GitLab' 'pull' 'Fetches remote issues and discussion notes from GitLab REST API into local markdown work item files.')
                    (New-MenuItem 'Push to GitLab' 'push' 'Publishes locally modified work items (marked with Sync Action: push) to GitLab issue tracker.' -MultiAction)
                    (New-MenuItem 'Regenerate tasklist' 'generate_list' 'Rebuilds the master .rivet/workitems-list.md dashboard aggregating all active, completed, and pending work items.')
                )
                if ($null -eq $taskAction) { continue }
                $p = [ordered]@{}
                switch ($taskAction) {
                    'list' {
                        $p.WorkItems = $true
                        $p.ListIssues = $true
                        Invoke-ReviewedWorkflow -Title 'List local work items' -Parameters $p
                    }
                    'view' {
                        $iidText = Read-OptionalValue 'Issue IID to view'
                        $iid = 0
                        if (-not [int]::TryParse($iidText, [ref]$iid) -or $iid -le 0) {
                            [Console]::WriteLine((Format-AnsiText -Text 'Valid issue IID is required.' -Color @(255, 90, 105) -Bold))
                            $null = [Console]::ReadKey($true)
                            continue
                        }
                        $p.WorkItems = $true
                        $p.ViewIssue = $true
                        $p.IssueIid = $iid
                        Invoke-ReviewedWorkflow -Title "View work item #$iid" -Parameters $p
                    }
                    'new' {
                        $title = Read-OptionalValue 'Issue title'
                        if ([string]::IsNullOrWhiteSpace($title)) {
                            [Console]::WriteLine((Format-AnsiText -Text 'Issue title is required.' -Color @(255, 90, 105) -Bold))
                            $null = [Console]::ReadKey($true)
                            continue
                        }
                        $p.WorkItems = $true
                        $p.NewIssue = $true
                        $p.IssueTitle = $title
                        $iidText = Read-OptionalValue 'GitLab IID (optional; 0 for new local item)' '0'
                        $iid = 0
                        if ([int]::TryParse($iidText, [ref]$iid) -and $iid -gt 0) { $p.IssueIid = $iid }
                        $labelsText = Read-OptionalValue 'Comma-separated labels (e.g. feature, ui)'
                        if (-not [string]::IsNullOrWhiteSpace($labelsText)) {
                            $p.IssueLabels = @($labelsText.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ })
                        }
                        Invoke-ReviewedWorkflow -Title "Scaffold work item: $title" -Parameters $p
                    }
                    'close' {
                        $iidText = Read-OptionalValue 'Issue IID to close'
                        $iid = 0
                        if (-not [int]::TryParse($iidText, [ref]$iid) -or $iid -le 0) {
                            [Console]::WriteLine((Format-AnsiText -Text 'Valid issue IID is required.' -Color @(255, 90, 105) -Bold))
                            $null = [Console]::ReadKey($true)
                            continue
                        }
                        $p.WorkItems = $true
                        $p.CloseIssue = $true
                        $p.IssueIid = $iid
                        Invoke-ReviewedWorkflow -Title "Close work item #$iid" -Parameters $p
                    }
                    'reopen' {
                        $iidText = Read-OptionalValue 'Issue IID to reopen'
                        $iid = 0
                        if (-not [int]::TryParse($iidText, [ref]$iid) -or $iid -le 0) {
                            [Console]::WriteLine((Format-AnsiText -Text 'Valid issue IID is required.' -Color @(255, 90, 105) -Bold))
                            $null = [Console]::ReadKey($true)
                            continue
                        }
                        $p.WorkItems = $true
                        $p.ReopenIssue = $true
                        $p.IssueIid = $iid
                        Invoke-ReviewedWorkflow -Title "Reopen work item #$iid" -Parameters $p
                    }
                    'pull' {
                        $p.WorkItems = $true
                        $p.PullIssues = $true
                        $iidText = Read-OptionalValue 'GitLab IID to pull (optional; blank pulls all marked items)'
                        $iid = 0
                        if ([int]::TryParse($iidText, [ref]$iid) -and $iid -gt 0) { $p.IssueIid = $iid }
                        $force = Select-YesNo -Title 'FORCE REFRESH (BYPASS CACHE)?' -Default $false
                        if ($null -eq $force) { continue }
                        if ($force) { $p.ForceRefresh = $true }
                        Invoke-ReviewedWorkflow -Title 'Pull GitLab issues' -Parameters $p
                    }
                    'push' {
                        $p.WorkItems = $true
                        $p.PushIssues = $true
                        if (-not (Select-PreviewMode $p)) { continue }
                        Invoke-ReviewedWorkflow -Title 'Push work items to GitLab' -Parameters $p
                    }
                    'generate_list' {
                        $p.WorkItems = $true
                        $p.GenerateList = $true
                        Invoke-ReviewedWorkflow -Title 'Regenerate workitems-list.md dashboard' -Parameters $p
                    }
                }
            }
            'help' {
                $topic = Read-OptionalValue 'Parameter name or alias; blank opens overview'
                $p = [ordered]@{ Help = $true }
                if ($topic) { $p.HelpParameter = $topic }
                Invoke-ReviewedWorkflow -Title 'rivet manual' -Parameters $p
            }
        }
    }
    } finally {
        # Restore the terminal even if a helper is removed after module import.
        # The direct ANSI fallback keeps cleanup independent from mutable files.
        $showCursor = Get-Command -Name Show-TerminalCursor -CommandType Function -ErrorAction SilentlyContinue
        if ($showCursor) { Show-TerminalCursor } else { [Console]::Write("$([char]27)[?25h") }
        $disableAltBuffer = Get-Command -Name Disable-TerminalAltBuffer -CommandType Function -ErrorAction SilentlyContinue
        if ($disableAltBuffer) { Disable-TerminalAltBuffer } else { [Console]::Write("$([char]27)[?1049l") }
    }
}
