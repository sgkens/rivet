<#
.SYNOPSIS
    Opens the reusable glmeta workflow menu.
.DESCRIPTION
    Builds reviewed run.ps1 invocations for local metadata, release documents,
    merge requests, GitLab metadata, Conventional Commits, Git history, and
    help. Workflow defaults avoid unrelated writes and destructive choices.
.PARAMETER RunnerPath
    Absolute or relative path to the glmeta run.ps1 entry point.
.PARAMETER ConfigPath
    Path to repo_config.json used for the project display name.
.PARAMETER RepositoryRoot
    Consuming repository operated on by reviewed runner commands.
.EXAMPLE
    Invoke-GlmetaMenu -RunnerPath ./glmeta/run.ps1 -ConfigPath ./repo_config.json -RepositoryRoot ./
#>
function Invoke-GlmetaMenu {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RunnerPath,
        [Parameter(Mandatory)][string]$ConfigPath,
        [Parameter(Mandatory)][string]$RepositoryRoot
    )

    if ([Console]::IsInputRedirected -or [Console]::IsOutputRedirected) {
        throw 'The glmeta menu requires an interactive terminal. Use run.ps1 help for non-interactive usage.'
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
        $displayLabel = if ($MultiAction) { "[MA] $Label" } else { $Label }
        [pscustomobject]@{
            Label = $displayLabel
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
        $prompt = if ([string]::IsNullOrWhiteSpace($Default)) { "$Label [optional]" } else { "$Label [$Default]" }
        $value = Read-Host $prompt
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
        $parts.Add('./glm.ps1')
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
        [Console]::WriteLine('')
        [Console]::WriteLine((Format-AnsiText -Text 'COMMAND REVIEW' -Color @(0, 200, 255) -Bold))
        [Console]::WriteLine((Format-AnsiText -Text $Title -Color @(220, 225, 235) -Bold))
        [Console]::WriteLine((Format-AnsiText -Text (Format-RunnerCommand $Parameters) -Color @(80, 220, 150)))
        [Console]::WriteLine('')
        $runChoice = Select-MenuValue -Title 'RUN THIS WORKFLOW?' -Items @(
            (New-MenuItem 'Run command' 'run' 'execute the reviewed parameters')
            (New-MenuItem 'Back' 'back' 'return without running')
        )
        if ($runChoice -ne 'run') { return }
        [Console]::WriteLine('')
        try {
            & $resolvedRunner -RepositoryRoot $repositoryRoot @Parameters
        } catch {
            [Console]::WriteLine((Format-AnsiText -Text "FAILED  $($_.Exception.Message)" -Color @(255, 90, 105) -Bold))
        }
        [Console]::WriteLine('')
        [Console]::WriteLine((Format-AnsiText -Text 'Press any key to return to the glmeta menu.' -Color @(145, 155, 175)))
        $null = [Console]::ReadKey($true)
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

    $menuAsciiHeader = @'
 ⢀⡀ ⡇ ⣀⣀  ⢀⡀ ⣰⡀ ⢀⣀   ⠄ ⣀⡀ ⣰⡀ ⢀⡀ ⡀⣀ ⢀⣀ ⢀⣀ ⣰⡀ ⠄ ⡀⢀ ⢀⡀   ⡷⢾ ⢀⡀ ⣀⡀ ⡀⢀
 ⣑⡺ ⠣ ⠇⠇⠇ ⠣⠭ ⠘⠤ ⠣⠼   ⠇ ⠇⠸ ⠘⠤ ⠣⠭ ⠏  ⠣⠼ ⠣⠤ ⠘⠤ ⠇ ⠱⠃ ⠣⠭   ⠇⠸ ⠣⠭ ⠇⠸ ⠣⠼
'@
    $menuHeaderTokens = ConvertTo-AsciiTokens -Lines ($menuAsciiHeader -split '\r?\n') -Connectivity 8
    $mainItems = @(
        (New-MenuItem 'Initialize repository' 'init' 'create or validate root configuration' -MultiAction)
        (New-MenuItem 'Prep Release' 'prep_release' 'manifests, release docs, READMEs, and mr.md' -MultiAction)
        (New-MenuItem 'Local metadata' 'local' 'version, README header, and TOC' -MultiAction)
        (New-MenuItem 'Release documents' 'release' 'draft or finalize changelog and notes')
        (New-MenuItem 'Merge request' 'merge_request' 'generate the managed mr.md document' -MultiAction)
        (New-MenuItem 'GitLab metadata' 'gitlab' 'description, topics, and labels')
        (New-MenuItem 'Conventional Commit' 'commit' 'review and submit repository changes' -MultiAction)
        (New-MenuItem 'Tag and publish' 'tag' 'snapshot checkpoint or production release')
        (New-MenuItem 'Git history' 'history' 'detailed enriched one-line log')
        (New-MenuItem 'Repository status' 'status' 'version, upstream, worktree, and next tags')
        (New-MenuItem 'Version report' 'version_report' 'explain baseline and bump inputs')
        (New-MenuItem 'Doctor' 'doctor' 'validate dependencies and configuration')
        (New-MenuItem 'Help' 'help' 'manual and parameter knowledge')
        (New-MenuItem 'Exit' 'exit')
    )

    while ($true) {
        [Console]::Clear()
        foreach ($headerLine in @(ConvertTo-GradientAsciiLines -TokenObject $menuHeaderTokens -Mode Horizontal -StartColor @(0, 200, 255) -EndColor @(255, 60, 180))) {
            [Console]::WriteLine($headerLine)
        }
        [Console]::Write((Format-AnsiText -Text 'GLMETA COMMAND CENTER  ' -Color @(220, 225, 235) -Bold))
        [Console]::Write((Format-AnsiText -Text $projectName -Color @(80, 220, 150) -Bold))
        [Console]::Write((Format-AnsiText -Text '  ' -Color @(145, 155, 175)))
        [Console]::Write((Format-AnsiText -Text $packageName -Color @(0, 200, 255)))
        [Console]::WriteLine((Format-AnsiText -Text " v$packageVersion" -Color @(255, 195, 75) -Bold))
        [Console]::WriteLine((Format-AnsiText -Text 'Every workflow is reviewed before execution.' -Color @(145, 155, 175)))
        [Console]::Write((Format-AnsiText -Text '[MA]' -Color @(190, 100, 255) -Bold))
        [Console]::WriteLine((Format-AnsiText -Text ' runs multiple glmeta actions in one reviewed workflow.' -Color @(110, 120, 145)))
        [Console]::WriteLine('')
        $action = Select-MenuValue -Title 'SELECT WORKFLOW' -Items $mainItems
        if ($null -eq $action -or $action -eq 'exit') { return }

        switch ($action) {
            'init' {
                $kind = Select-MenuValue -Title 'INITIALIZE REPOSITORY' -Items @(
                    (New-MenuItem 'Local configuration' 'local' 'create or validate root configuration only')
                    (New-MenuItem 'Configuration and GitLab' 'gitlab' 'initialize then synchronize project metadata' -MultiAction)
                )
                if ($null -eq $kind) { continue }
                $p = if ($kind -eq 'gitlab') { [ordered]@{ Bootstrap = $true } } else { [ordered]@{ Init = $true } }
                if (-not (Select-PreviewMode $p)) { continue }
                Invoke-ReviewedWorkflow -Title $(if ($kind -eq 'gitlab') { 'Initialize repository and GitLab metadata' } else { 'Initialize repository configuration' }) -Parameters $p
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
                )
                if ($null -eq $kind) { continue }
                $p = [ordered]@{}
                Add-IsolatedActionDefaults $p
                if ($kind -eq 'finalize') { $p.FinalizeRelease = $true } else { $p.UpdateReleaseDocs = $true }
                if (-not (Add-DocumentOptions $p)) { continue }
                if (-not (Add-ChangelogJsonOption $p)) { continue }
                if (-not (Select-PreviewMode $p)) { continue }
                Invoke-ReviewedWorkflow -Title 'Release documentation' -Parameters $p
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
            'help' {
                $topic = Read-OptionalValue 'Parameter name or alias; blank opens overview'
                $p = [ordered]@{ Help = $true }
                if ($topic) { $p.HelpParameter = $topic }
                Invoke-ReviewedWorkflow -Title 'glmeta manual' -Parameters $p
            }
        }
    }
}
