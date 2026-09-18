<#
.SYNOPSIS
    Argument completers and validation classes for Rivet cmdlets and runner.
.DESCRIPTION
    Provides dynamic and static tab-completion for Invoke-Rivet commands,
    commit types, commit scopes, changed files, parameter help topics,
    git tags, and branches. Includes examples for implementing custom
    IArgumentCompleter classes and registering them via Register-ArgumentCompleter.

.EXAMPLE
    # Class-based Argument Completer Pattern:
    # 1. Define a class implementing System.Management.Automation.IArgumentCompleter:
    class MyCustomCompleter : System.Management.Automation.IArgumentCompleter {
        [System.Collections.Generic.IEnumerable[System.Management.Automation.CompletionResult]] CompleteArgument(
            [string]$commandName,
            [string]$parameterName,
            [string]$wordToComplete,
            [System.Management.Automation.Language.CommandAst]$commandAst,
            [System.Collections.IDictionary]$fakeBoundParameters
        ) {
            $results = [System.Collections.Generic.List[System.Management.Automation.CompletionResult]]::new()
            $candidates = @('alpha', 'beta', 'gamma')
            foreach ($candidate in $candidates) {
                if ($candidate -like "$wordToComplete*") {
                    $results.Add([System.Management.Automation.CompletionResult]::new(
                        $candidate,                                                                # CompletionText
                        $candidate,                                                                # ListItemText
                        [System.Management.Automation.CompletionResultType]::ParameterValue,       # ResultType
                        "Description for $candidate"                                               # ToolTip
                    ))
                }
            }
            return $results
        }
    }

    # 2. Attach to a cmdlet parameter using the [ArgumentCompleter] attribute:
    # function Invoke-Example {
    #     param(
    #         [ArgumentCompleter([MyCustomCompleter])]
    #         [string]$Mode
    #     )
    # }

    # 3. Or register dynamically with Register-ArgumentCompleter:
    # Register-ArgumentCompleter -CommandName 'Invoke-Example' -ParameterName 'Mode' -CompleterType ([MyCustomCompleter])
#>

using namespace System.Management.Automation
using namespace System.Management.Automation.Language
using namespace System.Collections
using namespace System.Collections.Generic
using namespace System.IO

class RivetCommandCompleter : IArgumentCompleter {
    [IEnumerable[CompletionResult]] CompleteArgument(
        [string]$commandName,
        [string]$parameterName,
        [string]$wordToComplete,
        [CommandAst]$commandAst,
        [IDictionary]$fakeBoundParameters
    ) {
        $results = [List[CompletionResult]]::new()
        $commands = @(
            @{ Name = 'help'; ToolTip = 'Open the complete rivet manual or inspect a specific parameter.' }
            @{ Name = 'menu'; ToolTip = 'Open the interactive rivet command center.' }
            @{ Name = 'init'; ToolTip = 'Initialize repository-root rivet configuration.' }
            @{ Name = 'bootstrap'; ToolTip = 'Initialize configuration and synchronize GitLab metadata.' }
            @{ Name = 'prep-release'; ToolTip = 'Prepare all standard release metadata (manifests, docs, mr.md).' }
            @{ Name = 'doctor'; ToolTip = 'Validate rivet repository readiness and configuration health.' }
            @{ Name = 'status'; ToolTip = 'Show repository and release state (branch, calculated version, next tags).' }
            @{ Name = 'version'; ToolTip = 'Explain the next version calculation and commit bump inputs.' }
            @{ Name = 'readme'; ToolTip = 'Validate required README heading structure.' }
            @{ Name = 'commit'; ToolTip = 'Open the reviewed Conventional Commit workflow.' }
            @{ Name = 'tag'; ToolTip = 'Review, create, and push a release or snapshot tag.' }
            @{ Name = 'history'; ToolTip = 'Open the exclusive detailed Git history view (alias glo).' }
            @{ Name = 'glo'; ToolTip = 'Open the exclusive detailed Git history view.' }
            @{ Name = 'rebuild-changelog'; ToolTip = 'Rebuild complete CHANGELOG.md and changelog.json across all Git tags from history.' }
            @{ Name = 'flow'; ToolTip = 'Render the interactive ASCII flow graph of Rivet lifecycle (alias pipeline).' }
            @{ Name = 'pipeline'; ToolTip = 'Render the interactive ASCII flow graph of Rivet lifecycle.' }
            @{ Name = 'work-items'; ToolTip = 'List, pull, push, or scaffold local work items and GitLab issues (alias issues, tasks, wi).' }
            @{ Name = 'issues'; ToolTip = 'Manage local work items and GitLab issues.' }
            @{ Name = 'tasks'; ToolTip = 'Manage, list, or view repository tasks and work items.' }
            @{ Name = 'tasklist'; ToolTip = 'View or regenerate the aggregated repository task tracker dashboard.' }
            @{ Name = 'wi'; ToolTip = 'Work item management shorthand alias.' }
            @{ Name = 'sync-issues'; ToolTip = 'Synchronize local work items with remote GitLab issues.' }
            @{ Name = 'workitem'; ToolTip = 'Manage or create a work item.' }
            @{ Name = 'template'; ToolTip = 'Scaffold a new work item template formatted with metadata tables.' }
            @{ Name = 'view'; ToolTip = 'View complete work item details, description, acceptance criteria, and notes.' }
            @{ Name = 'close'; ToolTip = 'Close a work item and flag for push sync.' }
            @{ Name = 'reopen'; ToolTip = 'Reopen a closed work item and flag for push sync.' }
            @{ Name = 'generate-list'; ToolTip = 'Regenerate the aggregated workitems-list.md dashboard index.' }
        )

        foreach ($cmd in $commands) {
            if ($cmd.Name -like "$wordToComplete*") {
                $results.Add([CompletionResult]::new(
                    $cmd.Name,
                    $cmd.Name,
                    [CompletionResultType]::ParameterValue,
                    $cmd.ToolTip
                ))
            }
        }
        return $results
    }
}

class RivetCommitTypeCompleter : IArgumentCompleter {
    [IEnumerable[CompletionResult]] CompleteArgument(
        [string]$commandName,
        [string]$parameterName,
        [string]$wordToComplete,
        [CommandAst]$commandAst,
        [IDictionary]$fakeBoundParameters
    ) {
        $results = [List[CompletionResult]]::new()
        $types = [List[hashtable]]::new()

        # Try to resolve types dynamically from repository configuration
        $configLoaded = $false
        $repoPath = if ($fakeBoundParameters -and $fakeBoundParameters.ContainsKey('RepositoryRoot')) {
            [string]$fakeBoundParameters['RepositoryRoot']
        } else {
            (Get-Location).Path
        }

        $configPath = if ($fakeBoundParameters -and $fakeBoundParameters.ContainsKey('ConfigPath')) {
            [string]$fakeBoundParameters['ConfigPath']
        } else {
            [Path]::Combine($repoPath, 'repo_config.json')
        }

        if ([File]::Exists($configPath)) {
            try {
                $rawJson = [File]::ReadAllText($configPath)
                $config = [System.Text.Json.JsonDocument]::Parse($rawJson)
                if ($config.RootElement.TryGetProperty('commit', [ref]$null)) {
                    $commitElement = $config.RootElement.GetProperty('commit')
                    if ($commitElement.TryGetProperty('types', [ref]$null)) {
                        foreach ($t in $commitElement.GetProperty('types').EnumerateArray()) {
                            $name = $t.GetProperty('name').GetString()
                            $desc = if ($t.TryGetProperty('description', [ref]$null)) { $t.GetProperty('description').GetString() } else { '' }
                            $types.Add(@{ Name = $name; Description = $desc })
                        }
                        $configLoaded = $true
                    }
                }
                $config.Dispose()
            } catch {
                # Fallback to defaults
            }
        }

        if (-not $configLoaded -or $types.Count -eq 0) {
            $defaultTypes = @(
                @{ Name = 'feat'; Description = 'A new feature' }
                @{ Name = 'fix'; Description = 'A bug fix' }
                @{ Name = 'docs'; Description = 'Documentation only changes' }
                @{ Name = 'style'; Description = 'Changes that do not affect the meaning of the code' }
                @{ Name = 'refactor'; Description = 'A code change that neither fixes a bug nor adds a feature' }
                @{ Name = 'perf'; Description = 'A code change that improves performance' }
                @{ Name = 'test'; Description = 'Adding missing tests or correcting existing tests' }
                @{ Name = 'build'; Description = 'Changes that affect the build system or external dependencies' }
                @{ Name = 'ci'; Description = 'Changes to CI configuration files and scripts' }
                @{ Name = 'chore'; Description = "Other changes that don't modify src or test files" }
                @{ Name = 'revert'; Description = 'Reverts a previous commit' }
            )
            foreach ($dt in $defaultTypes) { $types.Add($dt) }
        }

        foreach ($t in $types) {
            if ($t.Name -like "$wordToComplete*") {
                $toolTip = if ($t.Description) { "$($t.Name): $($t.Description)" } else { $t.Name }
                $results.Add([CompletionResult]::new(
                    $t.Name,
                    $t.Name,
                    [CompletionResultType]::ParameterValue,
                    $toolTip
                ))
            }
        }
        return $results
    }
}

class RivetCommitScopeCompleter : IArgumentCompleter {
    [IEnumerable[CompletionResult]] CompleteArgument(
        [string]$commandName,
        [string]$parameterName,
        [string]$wordToComplete,
        [CommandAst]$commandAst,
        [IDictionary]$fakeBoundParameters
    ) {
        $results = [List[CompletionResult]]::new()
        $scopes = [List[hashtable]]::new()

        $repoPath = if ($fakeBoundParameters -and $fakeBoundParameters.ContainsKey('RepositoryRoot')) {
            [string]$fakeBoundParameters['RepositoryRoot']
        } else {
            (Get-Location).Path
        }

        $configPath = if ($fakeBoundParameters -and $fakeBoundParameters.ContainsKey('ConfigPath')) {
            [string]$fakeBoundParameters['ConfigPath']
        } else {
            [Path]::Combine($repoPath, 'repo_config.json')
        }

        $configLoaded = $false
        if ([File]::Exists($configPath)) {
            try {
                $rawJson = [File]::ReadAllText($configPath)
                $config = [System.Text.Json.JsonDocument]::Parse($rawJson)
                if ($config.RootElement.TryGetProperty('commit', [ref]$null)) {
                    $commitElement = $config.RootElement.GetProperty('commit')
                    if ($commitElement.TryGetProperty('scopes', [ref]$null)) {
                        foreach ($s in $commitElement.GetProperty('scopes').EnumerateArray()) {
                            $name = $s.GetProperty('name').GetString()
                            $desc = if ($s.TryGetProperty('description', [ref]$null)) { $s.GetProperty('description').GetString() } else { '' }
                            $scopes.Add(@{ Name = $name; Description = $desc })
                        }
                        $configLoaded = $true
                    }
                }
                $config.Dispose()
            } catch {
                # Fallback to defaults
            }
        }

        if (-not $configLoaded -or $scopes.Count -eq 0) {
            $defaultScopes = @(
                @{ Name = 'core'; Description = 'Core library implementation' }
                @{ Name = 'cli'; Description = 'Command-line interface and router' }
                @{ Name = 'ui'; Description = 'Terminal user interface elements' }
                @{ Name = 'docs'; Description = 'Documentation and examples' }
                @{ Name = 'release'; Description = 'Release preparation and metadata' }
                @{ Name = 'none'; Description = 'Omit scope parentheses from commit' }
            )
            foreach ($ds in $defaultScopes) { $scopes.Add($ds) }
        }

        foreach ($s in $scopes) {
            if ($s.Name -like "$wordToComplete*") {
                $toolTip = if ($s.Description) { "$($s.Name): $($s.Description)" } else { $s.Name }
                $results.Add([CompletionResult]::new(
                    $s.Name,
                    $s.Name,
                    [CompletionResultType]::ParameterValue,
                    $toolTip
                ))
            }
        }
        return $results
    }
}

class RivetCommitFilesCompleter : IArgumentCompleter {
    [IEnumerable[CompletionResult]] CompleteArgument(
        [string]$commandName,
        [string]$parameterName,
        [string]$wordToComplete,
        [CommandAst]$commandAst,
        [IDictionary]$fakeBoundParameters
    ) {
        $results = [List[CompletionResult]]::new()
        $repoPath = if ($fakeBoundParameters -and $fakeBoundParameters.ContainsKey('RepositoryRoot')) {
            [string]$fakeBoundParameters['RepositoryRoot']
        } else {
            (Get-Location).Path
        }

        try {
            $statusLines = @(& git -C $repoPath status --porcelain=v1 --untracked-files=all 2>$null)
            foreach ($line in $statusLines) {
                if ($line.Length -lt 4) { continue }
                $statusFlag = $line.Substring(0, 2).Trim()
                $filePath = $line.Substring(3).Trim('"')
                if ($filePath -like "$wordToComplete*") {
                    $toolTip = "[$statusFlag] $filePath"
                    $results.Add([CompletionResult]::new(
                        $filePath,
                        $filePath,
                        [CompletionResultType]::ParameterValue,
                        $toolTip
                    ))
                }
            }
        } catch {
            # Non-git directory or git failure
        }
        return $results
    }
}

class RivetHelpParamCompleter : IArgumentCompleter {
    [IEnumerable[CompletionResult]] CompleteArgument(
        [string]$commandName,
        [string]$parameterName,
        [string]$wordToComplete,
        [CommandAst]$commandAst,
        [IDictionary]$fakeBoundParameters
    ) {
        $results = [List[CompletionResult]]::new()
        $parameters = @(
            @{ Name = 'Command'; ToolTip = 'Positional command name (help, menu, init, prep-release, doctor, status, version, readme, commit, tag, history)' }
            @{ Name = 'Help'; ToolTip = 'Open the complete rivet manual' }
            @{ Name = 'Menu'; ToolTip = 'Open the interactive rivet command center' }
            @{ Name = 'Init'; ToolTip = 'Initialize repository-root rivet configuration' }
            @{ Name = 'Bootstrap'; ToolTip = 'Initialize configuration and synchronize GitLab metadata' }
            @{ Name = 'Profile'; ToolTip = 'Select an installed repository profile for initialization' }
            @{ Name = 'Manifest'; ToolTip = 'Repository-relative manifest path for initialization' }
            @{ Name = 'Bun'; ToolTip = 'Include Bun runtime templates (bunfig.toml and bun.lock)' }
            @{ Name = 'PrepRelease'; ToolTip = 'Prepare all standard release metadata' }
            @{ Name = 'Doctor'; ToolTip = 'Validate rivet repository readiness' }
            @{ Name = 'Status'; ToolTip = 'Show repository and release state' }
            @{ Name = 'VersionReport'; ToolTip = 'Explain the next version calculation' }
            @{ Name = 'ValidateReadme'; ToolTip = 'Validate required README headings' }
            @{ Name = 'HelpParameter'; ToolTip = 'Select a detailed parameter manual page' }
            @{ Name = 'Param'; ToolTip = 'Alias for HelpParameter' }
            @{ Name = 'SkipVersion'; ToolTip = 'Skip SemVer and manifest synchronization' }
            @{ Name = 'SkipReadmeMetadata'; ToolTip = 'Skip the generated README project header' }
            @{ Name = 'SkipTableOfContents'; ToolTip = 'Skip README table-of-contents generation' }
            @{ Name = 'SkipReadmeValidation'; ToolTip = 'Skip required README heading validation' }
            @{ Name = 'UpdateReleaseDocs'; ToolTip = 'Generate draft changelog and release notes' }
            @{ Name = 'FinalizeRelease'; ToolTip = 'Generate finalized, dated release documentation' }
            @{ Name = 'RebuildChangelog'; ToolTip = 'Rebuild complete CHANGELOG.md and changelog.json across all Git tags from history' }
            @{ Name = 'Rebuild'; ToolTip = 'Alias for RebuildChangelog' }
            @{ Name = 'FlowGraph'; ToolTip = 'Render the interactive ASCII flow graph of Rivet lifecycle' }
            @{ Name = 'Flow'; ToolTip = 'Alias for FlowGraph' }
            @{ Name = 'Pipeline'; ToolTip = 'Alias for FlowGraph' }
            @{ Name = 'UpdateChangelogJson'; ToolTip = 'Generate complete documentation changelog data' }
            @{ Name = 'UpdateMergeRequest'; ToolTip = 'Generate the working merge-request document' }
            @{ Name = 'CreateGitLabMergeRequest'; ToolTip = 'Create a GitLab merge request from mr.md' }
            @{ Name = 'UpdateGitLabMergeRequest'; ToolTip = 'Update the matching open GitLab merge request' }
            @{ Name = 'ReleaseVersion'; ToolTip = 'Override the displayed release version' }
            @{ Name = 'FromTag'; ToolTip = 'Select an explicit reachable Git baseline ref' }
            @{ Name = 'MergeTargetBranch'; ToolTip = 'Set the merge-request target branch (default: main)' }
            @{ Name = 'IncludeCommitHash'; ToolTip = 'Include linked short hashes in generated change lists' }
            @{ Name = 'IncludeAuthor'; ToolTip = 'Include GitLab author mentions in generated change lists' }
            @{ Name = 'SyncGitLabMetadata'; ToolTip = 'Synchronize configured GitLab project metadata' }
            @{ Name = 'DeleteMissingLabels'; ToolTip = 'Delete managed GitLab labels absent from config' }
            @{ Name = 'Commit'; ToolTip = 'Open the reviewed Conventional Commit workflow' }
            @{ Name = 'CommitType'; ToolTip = 'Supply the Conventional Commit type (e.g. feat, fix)' }
            @{ Name = 'CommitScope'; ToolTip = 'Supply an exact Conventional Commit scope' }
            @{ Name = 'CommitDescription'; ToolTip = 'Supply the commit subject description' }
            @{ Name = 'CommitFiles'; ToolTip = 'Stage only explicitly selected changed paths' }
            @{ Name = 'CommitAll'; ToolTip = 'Select every changed path for the commit' }
            @{ Name = 'Tag'; ToolTip = 'Review, create, and push a release tag' }
            @{ Name = 'Snapshot'; ToolTip = 'Create a plain SemVer snapshot tag' }
            @{ Name = 'TagForce'; ToolTip = 'Allow non-interactive tag publication' }
            @{ Name = 'TagVersion'; ToolTip = 'Override the version used for a tag' }
            @{ Name = 'GitLog'; ToolTip = 'Open the exclusive detailed Git history view' }
            @{ Name = 'glo'; ToolTip = 'Alias for GitLog' }
            @{ Name = 'GitLogCount'; ToolTip = 'Set the maximum displayed commit count' }
            @{ Name = 'GitLogAll'; ToolTip = 'Read history from every Git ref' }
            @{ Name = 'WorkItems'; ToolTip = 'Manage local work items and GitLab issues' }
            @{ Name = 'SyncWorkItems'; ToolTip = 'Synchronize local work items with remote GitLab issues' }
            @{ Name = 'PullIssues'; ToolTip = 'Pull remote GitLab issues into local .rivet/work-items/' }
            @{ Name = 'PushIssues'; ToolTip = 'Push local .rivet/work-items/ to remote GitLab issues' }
            @{ Name = 'ListIssues'; ToolTip = 'List local work items in a formatted TUI table' }
            @{ Name = 'NewIssue'; ToolTip = 'Scaffold a new local work item template' }
            @{ Name = 'Template'; ToolTip = 'Scaffold a new work item template with metadata tables' }
            @{ Name = 'IssueIid'; ToolTip = 'Target a specific GitLab issue IID for pull or push' }
            @{ Name = 'Iid'; ToolTip = 'Alias for IssueIid' }
            @{ Name = 'ForceRefresh'; ToolTip = 'Bypass API cache when fetching remote issues' }
            @{ Name = 'RepositoryRoot'; ToolTip = 'Select the consuming repository root directory' }
            @{ Name = 'ConfigPath'; ToolTip = 'Override repository configuration file path' }
            @{ Name = 'DryRun'; ToolTip = 'Preview supported actions without applying writes' }
            @{ Name = 'Raw'; ToolTip = 'Suppress visual report cards and return structured objects' }
        )

        foreach ($p in $parameters) {
            if ($p.Name -like "$wordToComplete*") {
                $results.Add([CompletionResult]::new(
                    $p.Name,
                    $p.Name,
                    [CompletionResultType]::ParameterValue,
                    $p.ToolTip
                ))
            }
        }
        return $results
    }
}

class RivetTagCompleter : IArgumentCompleter {
    [IEnumerable[CompletionResult]] CompleteArgument(
        [string]$commandName,
        [string]$parameterName,
        [string]$wordToComplete,
        [CommandAst]$commandAst,
        [IDictionary]$fakeBoundParameters
    ) {
        $results = [List[CompletionResult]]::new()
        $repoPath = if ($fakeBoundParameters -and $fakeBoundParameters.ContainsKey('RepositoryRoot')) {
            [string]$fakeBoundParameters['RepositoryRoot']
        } else {
            (Get-Location).Path
        }

        try {
            $tags = @(& git -C $repoPath tag --list --sort=-creatordate 2>$null)
            foreach ($tag in $tags) {
                $trimmed = $tag.Trim()
                if ($trimmed -like "$wordToComplete*") {
                    $results.Add([CompletionResult]::new(
                        $trimmed,
                        $trimmed,
                        [CompletionResultType]::ParameterValue,
                        "Git tag: $trimmed"
                    ))
                }
            }
        } catch {
            # Non-git directory
        }
        return $results
    }
}

class RivetBranchCompleter : IArgumentCompleter {
    [IEnumerable[CompletionResult]] CompleteArgument(
        [string]$commandName,
        [string]$parameterName,
        [string]$wordToComplete,
        [CommandAst]$commandAst,
        [IDictionary]$fakeBoundParameters
    ) {
        $results = [List[CompletionResult]]::new()
        $repoPath = if ($fakeBoundParameters -and $fakeBoundParameters.ContainsKey('RepositoryRoot')) {
            [string]$fakeBoundParameters['RepositoryRoot']
        } else {
            (Get-Location).Path
        }

        try {
            $branches = @(& git -C $repoPath branch -a --format="%(refname:short)" 2>$null)
            foreach ($branch in $branches) {
                $trimmed = $branch.Trim()
                if ($trimmed -and $trimmed -like "$wordToComplete*") {
                    $results.Add([CompletionResult]::new(
                        $trimmed,
                        $trimmed,
                        [CompletionResultType]::ParameterValue,
                        "Git branch: $trimmed"
                    ))
                }
            }
        } catch {
            # Non-git directory
        }
        return $results
    }
}

function Register-RivetArgumentCompleters {
    [CmdletBinding()]
    param()

    $commands = @('Invoke-Rivet', 'rivet', 'run.ps1', './run.ps1', './run', 'run')

    foreach ($cmd in $commands) {
        Register-ArgumentCompleter -CommandName $cmd -ParameterName 'Command' -ScriptBlock {
            param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
            [RivetCommandCompleter]::new().CompleteArgument($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
        } -ErrorAction SilentlyContinue

        Register-ArgumentCompleter -CommandName $cmd -ParameterName 'CommitType' -ScriptBlock {
            param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
            [RivetCommitTypeCompleter]::new().CompleteArgument($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
        } -ErrorAction SilentlyContinue

        Register-ArgumentCompleter -CommandName $cmd -ParameterName 'CommitScope' -ScriptBlock {
            param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
            [RivetCommitScopeCompleter]::new().CompleteArgument($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
        } -ErrorAction SilentlyContinue

        Register-ArgumentCompleter -CommandName $cmd -ParameterName 'CommitFiles' -ScriptBlock {
            param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
            [RivetCommitFilesCompleter]::new().CompleteArgument($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
        } -ErrorAction SilentlyContinue

        Register-ArgumentCompleter -CommandName $cmd -ParameterName 'HelpParameter' -ScriptBlock {
            param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
            [RivetHelpParamCompleter]::new().CompleteArgument($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
        } -ErrorAction SilentlyContinue

        Register-ArgumentCompleter -CommandName $cmd -ParameterName 'Param' -ScriptBlock {
            param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
            [RivetHelpParamCompleter]::new().CompleteArgument($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
        } -ErrorAction SilentlyContinue

        Register-ArgumentCompleter -CommandName $cmd -ParameterName 'FromTag' -ScriptBlock {
            param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
            [RivetTagCompleter]::new().CompleteArgument($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
        } -ErrorAction SilentlyContinue

        Register-ArgumentCompleter -CommandName $cmd -ParameterName 'MergeTargetBranch' -ScriptBlock {
            param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
            [RivetBranchCompleter]::new().CompleteArgument($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
        } -ErrorAction SilentlyContinue

        Register-ArgumentCompleter -CommandName $cmd -ParameterName 'Profile' -ScriptBlock {
            param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
            $profilesRoot = [System.IO.Path]::Combine($PSScriptRoot, '..', '..', 'profiles')
            $results = [System.Collections.Generic.List[System.Management.Automation.CompletionResult]]::new()
            if ([System.IO.Directory]::Exists($profilesRoot)) {
                foreach ($dir in [System.IO.Directory]::GetDirectories($profilesRoot)) {
                    $name = [System.IO.Path]::GetFileName($dir)
                    if ($name -like "$wordToComplete*" -and [System.IO.File]::Exists([System.IO.Path]::Combine($dir, 'profile.ps1'))) {
                        $results.Add([System.Management.Automation.CompletionResult]::new($name, $name, [System.Management.Automation.CompletionResultType]::ParameterValue, "Repository profile $name"))
                    }
                }
            }
            return $results
        } -ErrorAction SilentlyContinue
    }
}
