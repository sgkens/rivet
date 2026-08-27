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
            @((New-MenuItem 'Yes' $true), (New-MenuItem 'No' $false))
        } else {
            @((New-MenuItem 'No' $false), (New-MenuItem 'Yes' $true))
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
            (New-MenuItem 'Run command' 'run' 'execute the reviewed parameters')
            (New-MenuItem 'Back' 'back' 'return without running')
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
            (New-MenuItem 'Preview only' 'preview' 'recommended; do not write changes')
            (New-MenuItem 'Apply changes' 'apply' 'write the selected changes')
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
        (New-MenuItem 'Initialize repository' 'init' 'create or validate root configuration' -MultiAction)
        (New-MenuItem 'Prep Release' 'prep_release' 'manifests, release docs, READMEs, and mr.md' -MultiAction)
        (New-MenuItem 'Local metadata' 'local' 'version, README header, and TOC' -MultiAction)
        (New-MenuItem 'Release documents' 'release' 'draft or finalize changelog and notes')
        (New-MenuItem 'Merge request' 'merge_request' 'generate the managed mr.md document' -MultiAction)
        (New-MenuItem 'GitLab metadata' 'gitlab' 'description, topics, and labels')
        (New-MenuItem 'Conventional Commit' 'commit' 'review and submit repository changes' -MultiAction)
        (New-MenuItem 'Work items & tasks' 'work_items' 'list, view, scaffold, pull, push, and index tasks' -MultiAction)
        (New-MenuItem 'Tag and publish' 'tag' 'snapshot checkpoint or production release')
        (New-MenuItem 'Git history' 'history' 'detailed enriched one-line log')
        (New-MenuItem 'Repository status' 'status' 'version, upstream, worktree, and next tags')
        (New-MenuItem 'Version report' 'version_report' 'explain baseline and bump inputs')
        (New-MenuItem 'Doctor' 'doctor' 'validate dependencies and configuration')
        (New-MenuItem 'Pipeline flow graph' 'flow' 'visualize the Rivet automation and release lifecycle')
        (New-MenuItem 'Help' 'help' 'manual and parameter knowledge')
        (New-MenuItem 'Exit' 'exit')
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
                    (New-MenuItem 'Local configuration' 'local' 'create or validate root configuration only')
                    (New-MenuItem 'Local configuration (Bun)' 'local_bun' 'create configuration including bunfig.toml and bun.lock')
                    (New-MenuItem 'Configuration and GitLab' 'gitlab' 'initialize then synchronize project metadata' -MultiAction)
                    (New-MenuItem 'Configuration and GitLab (Bun)' 'gitlab_bun' 'initialize Bun repository then sync project metadata' -MultiAction)
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
                    (New-MenuItem 'Preview release preparation' 'preview' 'inspect every generated release file' -MultiAction)
                    (New-MenuItem 'Apply release preparation' 'apply' 'update manifests, docs, READMEs, and mr.md' -MultiAction)
                    (New-MenuItem 'Apply and commit' 'commit' 'update then review the release-file commit' -MultiAction)
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
                    (New-MenuItem 'Preview all' 'preview_all' 'version, header, and TOC without writes' -MultiAction)
                    (New-MenuItem 'Apply all' 'apply_all' 'version, header, and TOC' -MultiAction)
                    (New-MenuItem 'Version only' 'version' 'package.json and jsr.jsonc manifests')
                    (New-MenuItem 'README header only' 'header' 'configured project identity and badges')
                    (New-MenuItem 'README TOC only' 'toc' 'managed table of contents')
                    (New-MenuItem 'Validate README' 'validate_readme' 'required JavaScript library sections')
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
                    (New-MenuItem 'Generate draft' 'draft' 'update changelog and release notes')
                    (New-MenuItem 'Finalize release' 'finalize' 'write the dated release sections')
                    (New-MenuItem 'Rebuild changelog' 'rebuild' 'regenerate entire CHANGELOG.md across all tags' -MultiAction)
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
                    (New-MenuItem 'Generate mr.md' 'document' 'update the local merge-request document')
                    (New-MenuItem 'Generate and create on GitLab' 'create' 'publish a new merge request after generation' -MultiAction)
                    (New-MenuItem 'Generate and update on GitLab' 'update' 'replace the matching open merge request' -MultiAction)
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
                    (New-MenuItem 'Commit current changes' 'current' 'skip metadata generation')
                    (New-MenuItem 'Metadata and commit' 'metadata' 'run local metadata before committing' -MultiAction)
                    (New-MenuItem 'Preview commit' 'preview' 'do not stage repository changes')
                )
                if ($null -eq $kind) { continue }
                $p = [ordered]@{ Commit = $true }
                if ($kind -ne 'metadata') { Add-IsolatedActionDefaults $p }
                if ($kind -eq 'preview') { $p.DryRun = $true }
                Invoke-ReviewedWorkflow -Title 'Conventional Commit' -Parameters $p
            }
            'tag' {
                $kind = Select-MenuValue -Title 'TAG AND PUBLISH' -Items @(
                    (New-MenuItem 'Snapshot tag' 'snapshot' 'push plain SemVer for validation only')
                    (New-MenuItem 'Production tag' 'production' 'append -release and trigger publishing')
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
                    (New-MenuItem 'List tasks' 'list' 'render overview table of local work items')
                    (New-MenuItem 'View task details' 'view' 'inspect full description and criteria for an issue')
                    (New-MenuItem 'Scaffold new work item' 'new' 'create markdown template with metadata table')
                    (New-MenuItem 'Close task' 'close' 'mark closed and flag for push synchronization')
                    (New-MenuItem 'Reopen task' 'reopen' 'mark open and flag for push synchronization')
                    (New-MenuItem 'Pull from GitLab' 'pull' 'fetch remote issues and discussion notes into local markdown')
                    (New-MenuItem 'Push to GitLab' 'push' 'publish local changes to GitLab issue tracker' -MultiAction)
                    (New-MenuItem 'Regenerate tasklist' 'generate_list' 'rebuild the aggregated workitems-list.md dashboard')
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
