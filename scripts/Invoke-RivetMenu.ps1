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

    function New-MenuItem([string]$Label, [object]$Value, [string]$Description = '', [switch]$MultiAction, [string]$Command = '') {
        [pscustomobject]@{
            Label = $Label
            Value = $Value
            Description = $Description
            MultiAction = [bool]$MultiAction
            Command = $Command
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
        (New-MenuItem 'Initialize repository' 'init' 'Choose local npm or Bun scaffolding, or combine scaffolding with GitLab project metadata synchronization. Preview mode reports every target before any file or remote mutation.' -MultiAction -Command './rivet.ps1 init | bootstrap [-Bun] [-DryRun]')
        (New-MenuItem 'Prep Release' 'prep_release' 'Run the complete release-preparation chain: resolve SemVer, synchronize manifests and both README headers, generate release documents and mr.md, and optionally create the release commit.' -MultiAction -Command './rivet.ps1 prep-release [-DryRun] [-Commit]')
        (New-MenuItem 'Local metadata' 'local' 'Control each local metadata operation independently or run the combined set: manifest version synchronization, README/README-npm header generation, TOC generation, and README contract validation.' -MultiAction -Command './rivet.ps1 [metadata skip switches] [-DryRun]')
        (New-MenuItem 'Release documents' 'release' 'Choose draft generation, finalization, or full historical changelog reconstruction. Scope, baseline, attribution, JSON output, and preview behavior are configured before execution.' -MultiAction -Command './rivet.ps1 -UpdateReleaseDocs | -FinalizeRelease | -RebuildChangelog')
        (New-MenuItem 'Merge request' 'merge_request' 'Generate mr.md alone, or combine document generation with GitLab merge-request creation or update. The resolved source range and target branch are shown before execution.' -MultiAction -Command './rivet.ps1 -UpdateMergeRequest [-CreateGitLabMergeRequest|-UpdateGitLabMergeRequest]')
        (New-MenuItem 'GitLab metadata' 'gitlab' 'Compare repo_meta.json with the GitLab project, then preview or apply descriptions, topics, and managed labels. Deleting unmanaged remote labels requires a separate confirmation.' -Command './rivet.ps1 -SyncGitLabMetadata [-DeleteMissingLabels] [-DryRun]')
        (New-MenuItem 'Conventional Commit' 'commit' 'Choose an isolated commit, a dry-run commit review, or a combined metadata-and-commit workflow. File selection, Conventional Commit fields, and the final subject are reviewed before submission.' -MultiAction -Command './rivet.ps1 commit [-DryRun]')
        (New-MenuItem 'Work items & tasks' 'work_items' 'Access every local and GitLab work-item action: list, inspect, scaffold, close, reopen, pull, push, and regenerate the task dashboard. Remote writes remain explicit.' -MultiAction -Command './rivet.ps1 work-items [action switches]')
        (New-MenuItem 'Tag and publish' 'tag' 'Choose a snapshot CI tag or production publication tag. Rivet validates the worktree, manifests, branch state, and remote tag status before previewing or pushing.' -MultiAction -Command './rivet.ps1 tag [-Snapshot] [-TagVersion x.y.z] [-DryRun]')
        (New-MenuItem 'Git history' 'history' 'Render an enriched Git graph with configurable count, ref coverage, merge filtering, and Conventional Commit scope. This action is read-only.' -Command './rivet.ps1 history [-GitLogCount 25] [-GitLogAll] [-GitLogNoMerges]')
        (New-MenuItem 'Repository status' 'status' 'Inspect branch, HEAD, upstream divergence, worktree changes, manifest parity, release baseline, and projected snapshot and production tags without modifying the repository.' -Command './rivet.ps1 status')
        (New-MenuItem 'Version report' 'version_report' 'Explain the projected SemVer by scanning commits after the release baseline and classifying breaking, feature, fix, and non-release changes. This action is read-only.' -Command './rivet.ps1 version')
        (New-MenuItem 'Doctor' 'doctor' 'Run repository diagnostics for PowerShell, Git, runtime tools, configuration, identity, required files, manifest parity, lockfiles, credentials, and README contracts.' -Command './rivet.ps1 doctor')
        (New-MenuItem 'Pipeline flow graph' 'flow' 'Render the responsive Rivet lifecycle graph with terminal-width-aware FlowGraph wrapping. This action reads workflow structure only and performs no repository mutations.' -Command './rivet.ps1 flow')
        (New-MenuItem 'Help' 'help' 'Open the complete manual or request one parameter or alias. The pager covers command routing, switches, configuration contracts, and workflow interactions.' -Command './rivet.ps1 help [-HelpParameter name]')
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
                    (New-MenuItem 'Local configuration' 'local' 'Create repository configuration, metadata, JavaScript tooling, validation scripts, and CI files without contacting GitLab. Existing files are reported and preserved by the initializer.' -Command './rivet.ps1 init [-DryRun]')
                    (New-MenuItem 'Local configuration (Bun)' 'local_bun' 'Create the local repository scaffold plus Bun configuration and lockfile templates. No GitLab API operation is performed.' -Command './rivet.ps1 init -Bun [-DryRun]')
                    (New-MenuItem 'Configuration and GitLab' 'gitlab' 'Create the local npm/Node scaffold, then synchronize the configured GitLab description, topics, and managed label catalog.' -MultiAction -Command './rivet.ps1 bootstrap [-DryRun]')
                    (New-MenuItem 'Configuration and GitLab (Bun)' 'gitlab_bun' 'Create the Bun-oriented local scaffold, then synchronize the configured GitLab description, topics, and managed label catalog.' -MultiAction -Command './rivet.ps1 bootstrap -Bun [-DryRun]')
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
                    (New-MenuItem 'Preview release preparation' 'preview' 'Calculate and render every release-preparation result without writing files, creating commits, or publishing remote state.' -MultiAction -Command './rivet.ps1 prep-release -DryRun')
                    (New-MenuItem 'Apply release preparation' 'apply' 'Resolve the next version and update manifests, README headers, TOC, changelog, release notes, curated changelog JSON, and mr.md.' -MultiAction -Command './rivet.ps1 prep-release')
                    (New-MenuItem 'Apply and commit' 'commit' 'Apply the complete release-preparation chain, select the generated release files, and create a reviewed chore(release) commit.' -MultiAction -Command './rivet.ps1 prep-release -Commit -CommitType chore -CommitScope release')
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
                    (New-MenuItem 'Preview all' 'preview_all' 'Preview manifest version resolution, both README headers, TOC generation, and README validation without changing the worktree.' -MultiAction -Command './rivet.ps1 -DryRun')
                    (New-MenuItem 'Apply all' 'apply_all' 'Synchronize manifest versions, README and README-npm headers, the managed README TOC, and required-heading validation in one run.' -MultiAction -Command './rivet.ps1')
                    (New-MenuItem 'Version only' 'version' 'Calculate the Conventional Commit bump and write only package.json and jsr.jsonc; README and documentation operations are skipped.' -Command './rivet.ps1 -SkipReadmeMetadata -SkipTableOfContents')
                    (New-MenuItem 'README headers only' 'header' 'Regenerate the metadata-driven headers in README.md and README-npm.md while leaving manifests, TOC content, and release documents unchanged.' -Command './rivet.ps1 -SkipVersion -SkipTableOfContents')
                    (New-MenuItem 'README TOC only' 'toc' 'Regenerate only the managed H2-H4 table of contents in README.md; manifest and header synchronization are skipped.' -Command './rivet.ps1 -SkipVersion -SkipReadmeMetadata')
                    (New-MenuItem 'Validate README' 'validate_readme' 'Audit README.md against the required heading contract in repo_config.json without modifying either README.' -Command './rivet.ps1 readme')
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
                if ($choice -in @('version', 'header', 'toc') -and -not (Select-PreviewMode $p)) { continue }
                Invoke-ReviewedWorkflow -Title 'Local repository metadata' -Parameters $p
            }
            'release' {
                $kind = Select-MenuValue -Title 'RELEASE DOCUMENTS' -Items @(
                    (New-MenuItem 'Generate draft' 'draft' 'Read Conventional Commits after the selected baseline and refresh the unreleased sections in CHANGELOG.md and release-notes.md. Optional scope and attribution filters are applied consistently.' -Command './rivet.ps1 -UpdateReleaseDocs [-FromTag tag] [-DryRun]')
                    (New-MenuItem 'Finalize release' 'finalize' 'Convert the pending release range into a dated version section in CHANGELOG.md and release-notes.md using the resolved or overridden version.' -Command './rivet.ps1 -FinalizeRelease [-ReleaseVersion x.y.z] [-DryRun]')
                    (New-MenuItem 'Rebuild changelog' 'rebuild' 'Traverse all reachable release tags and rebuild the complete CHANGELOG.md plus optional docs/data/changelog.json output.' -MultiAction -Command './rivet.ps1 rebuild-changelog [-UpdateChangelogJson] [-DryRun]')
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
                    (New-MenuItem 'Generate mr.md' 'document' 'Build the local merge-request document from the selected commit range, target branch, version, scope, author data, and managed template sections.' -Command './rivet.ps1 -UpdateMergeRequest [-MergeTargetBranch main] [-DryRun]')
                    (New-MenuItem 'Generate and create on GitLab' 'create' 'Generate mr.md, validate its managed metadata, then create a GitLab merge request for the current source branch.' -MultiAction -Command './rivet.ps1 -UpdateMergeRequest -CreateGitLabMergeRequest [-DryRun]')
                    (New-MenuItem 'Generate and update on GitLab' 'update' 'Regenerate mr.md, resolve the existing merge-request IID, then update its GitLab title and description.' -MultiAction -Command './rivet.ps1 -UpdateMergeRequest -UpdateGitLabMergeRequest [-DryRun]')
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
                    (New-MenuItem 'Commit current changes' 'current' 'Select changed files, inspect the patch, choose Conventional Commit type and scope, and confirm the final subject before Git creates the commit.' -Command './rivet.ps1 commit')
                    (New-MenuItem 'Metadata and commit' 'metadata' 'Synchronize version and README metadata first, then select the resulting changes and complete the Conventional Commit review.' -MultiAction -Command './rivet.ps1 commit [metadata actions enabled]')
                    (New-MenuItem 'Preview commit' 'preview' 'Run the complete commit selection and message review without invoking git commit or modifying repository files.' -Command './rivet.ps1 commit -DryRun')
                )
                if ($null -eq $kind) { continue }
                $p = [ordered]@{ Commit = $true }
                if ($kind -ne 'metadata') { Add-IsolatedActionDefaults $p }
                if ($kind -eq 'preview') { $p.DryRun = $true }
                Invoke-ReviewedWorkflow -Title 'Conventional Commit' -Parameters $p
            }
            'tag' {
                $kind = Select-MenuValue -Title 'TAG AND PUBLISH' -Items @(
                    (New-MenuItem 'Snapshot tag' 'snapshot' 'Validate the clean worktree, branch, upstream, manifests, and existing tags before creating a plain SemVer CI-validation tag.' -Command './rivet.ps1 tag -Snapshot [-TagVersion x.y.z] [-DryRun]')
                    (New-MenuItem 'Production tag' 'production' 'Validate publication readiness before creating the configured release-suffix tag that triggers package and release pipelines.' -Command './rivet.ps1 tag [-TagVersion x.y.z] [-DryRun]')
                )
                if ($null -eq $kind) { continue }
                $p = [ordered]@{ Tag = $true }
                if ($kind -eq 'snapshot') { $p.Snapshot = $true }
                $version = Read-OptionalValue 'Version override; blank calculates from commits'
                if ($version) { $p.TagVersion = $version }
                $forceTag = Select-YesNo -Title 'REPLACE AN EXISTING LOCAL TAG?' -Default $false
                if ($null -eq $forceTag) { continue }
                if ($forceTag) { $p.TagForce = $true }
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
                    (New-MenuItem 'List tasks' 'list' 'Read every local work-item file and render IID, title, status, milestone, labels, and pending synchronization state without contacting GitLab.' -Command './rivet.ps1 work-items -ListIssues')
                    (New-MenuItem 'View task details' 'view' 'Open one local work item by IID, including metadata, description, acceptance criteria, discussion notes, and synchronization state.' -Command './rivet.ps1 view -IssueIid <iid>')
                    (New-MenuItem 'Scaffold new work item' 'new' 'Create one local work-item Markdown file from the standard template with title, optional IID, labels, metadata, and acceptance-criteria sections.' -Command './rivet.ps1 template -IssueTitle <title>')
                    (New-MenuItem 'Close task' 'close' 'Set one local work item to closed, mark it for a later push, and regenerate the aggregate task dashboard.' -Command './rivet.ps1 close -IssueIid <iid>')
                    (New-MenuItem 'Reopen task' 'reopen' 'Set one closed local work item back to opened, mark it for a later push, and regenerate the aggregate task dashboard.' -Command './rivet.ps1 reopen -IssueIid <iid>')
                    (New-MenuItem 'Pull from GitLab' 'pull' 'Fetch one IID or the configured issue set from GitLab, refresh local metadata and notes, and optionally bypass the local API cache.' -Command './rivet.ps1 work-items -PullIssues [-IssueIid <iid>] [-ForceRefresh]')
                    (New-MenuItem 'Push to GitLab' 'push' 'Process all local work items marked for push, creating or updating GitLab issues and reconciling returned IIDs and synchronization state.' -MultiAction -Command './rivet.ps1 work-items -PushIssues [-DryRun]')
                    (New-MenuItem 'Regenerate tasklist' 'generate_list' 'Rebuild .rivet/workitems-list.md from local work-item metadata without changing individual work items or remote issues.' -Command './rivet.ps1 generate-list')
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
                        $description = Read-OptionalValue 'Work-item description'
                        if ($description) { $p.IssueDescription = $description }
                        $milestone = Read-OptionalValue 'Milestone title'
                        if ($milestone) { $p.IssueMilestone = $milestone }
                        $state = Select-MenuValue -Title 'INITIAL WORK-ITEM STATE' -Items @(
                            (New-MenuItem 'Opened' 'opened' 'Create the local work item in the opened state.' -Command './rivet.ps1 template -IssueState opened')
                            (New-MenuItem 'Closed' 'closed' 'Create the local work item in the closed state.' -Command './rivet.ps1 template -IssueState closed')
                        )
                        if ($null -eq $state) { continue }
                        $p.IssueState = $state
                        if (-not (Select-PreviewMode $p)) { continue }
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
                        if (-not (Select-PreviewMode $p)) { continue }
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
                        if (-not (Select-PreviewMode $p)) { continue }
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
                        if (-not (Select-PreviewMode $p)) { continue }
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
                        if (-not (Select-PreviewMode $p)) { continue }
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
