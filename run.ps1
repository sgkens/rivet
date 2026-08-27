<#
.SYNOPSIS
    Runs repeatable repository metadata maintenance for a consuming repository.
.DESCRIPTION
    Entry script wrapper delegating directly to the Invoke-Rivet router cmdlet.
#>
[CmdletBinding(DefaultParameterSetName = 'Default')]
param(
    [Parameter(Position = 0, ParameterSetName = 'Default')]
    [ValidateSet('help', 'menu', 'init', 'bootstrap', 'prep-release', 'doctor', 'status', 'version', 'readme', 'commit', 'tag', 'history', 'glo', 'rebuild-changelog', 'flow', 'pipeline', 'work-items', 'issues', 'sync-issues', 'workitem', 'template', 'tasks', 'tasklist', 'wi', 'view', 'close', 'reopen', 'generate-list')]
    [string]$Command,

    [switch]$Help,
    [switch]$Menu,
    [switch]$Init,
    [switch]$Bootstrap,
    [switch]$Bun,
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
    [switch]$DryRun,
    [switch]$Raw
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$modulePath = [System.IO.Path]::Combine($PSScriptRoot, 'rivet.psd1')
$loadedRivet = Get-Module -Name rivet | Where-Object {
    [System.StringComparer]::OrdinalIgnoreCase.Equals(
        [System.IO.Path]::GetFullPath($_.ModuleBase),
        [System.IO.Path]::GetFullPath($PSScriptRoot)
    )
} | Select-Object -First 1
if (-not $loadedRivet) {
    Import-Module $modulePath -DisableNameChecking -ErrorAction Stop
}

Invoke-Rivet @PSBoundParameters
