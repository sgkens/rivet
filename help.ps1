<#
.SYNOPSIS
    Displays the rivet terminal manual.
.DESCRIPTION
    Renders a colored overview for run.ps1 or detailed knowledge and examples
    for one parameter. Parameter lookup is case-insensitive and accepts aliases.
.PARAMETER Param
    Runner parameter or alias to explain in detail.
.EXAMPLE
    ./rivet/help.ps1
.EXAMPLE
    ./rivet/help.ps1 -Param glo
#>
[CmdletBinding()]
param(
    [Alias('Parameter')]
    [string]$Param
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptsRoot = [System.IO.Path]::Combine($PSScriptRoot, 'scripts')
. ([System.IO.Path]::Combine($scriptsRoot, 'asciitokenizer.ps1'))

$asciiBanner = @'
   ┌───┐    █████  ████ ██   ██ ██████ ██████
  ╱▓▓▓▓▓╲   ██  ██  ██  ██   ██ ██      ██
 │▓█▓▓▓█▓│--█████   ██   ██ ██  █████    ██
  ╲▓▓▓▓▓╱   ██ ██   ██   ██ ██  ██        ██
   └─┼─┘    ██  ██ ████   ███   ██████   ██
     |      |    |  ||     ||    |  |    ||
     |      Repository automation reference
     |      ./help.ps1 -Param <name>
'@

function New-HelpEntry {
    param(
        [string]$Name, [string]$Type, [string]$Default, [string]$Summary,
        [string]$Details, [string]$Example, [string[]]$Aliases = @(),
        [string]$Values = 'Not restricted', [string]$Interactions = 'None.'
    )
    [pscustomobject]@{
        Name = $Name; Type = $Type; Default = $Default; Summary = $Summary
        Details = $Details; Example = $Example; Aliases = $Aliases
        Values = $Values; Interactions = $Interactions
    }
}

$entries = @(
    New-HelpEntry 'Command' 'string' 'unset' 'Select a positional runner command.' 'Provides command-style routing without duplicating implementation in run.ps1.' './rivet.ps1 prep-release -DryRun' -Values 'help, menu, init, bootstrap, prep-release, doctor, status, version, or readme.' -Interactions 'The help command accepts an optional second positional parameter name.'
    New-HelpEntry 'Help' 'switch' 'false' 'Open the complete rivet manual.' 'Dispatches directly to help.ps1 and exits before the metadata runner initializes.' './rivet.ps1 -Help' -Interactions 'Combine with -Param to open one detailed parameter page.'
    New-HelpEntry 'Menu' 'switch' 'false' 'Open the interactive rivet command center.' 'Dispatches to the persistent Show-SMenu workflow interface. Each workflow collects relevant options, prints the exact runner command, and requires review before execution.' './rivet.ps1 menu' -Interactions 'Requires an interactive terminal. Escape returns to the preceding menu or exits from the command center.'
    New-HelpEntry 'Init' 'switch' 'false' 'Initialize repository-root rivet configuration.' 'Infers defaults from the repository profile, Git, and origin; creates missing configuration and profile template files and validates an existing configuration without overwriting it.' './rivet.ps1 init -DryRun' -Interactions 'Exclusive. Use DryRun to preview. Existing files are never replaced.'
    New-HelpEntry 'Bootstrap' 'switch' 'false' 'Initialize configuration and synchronize GitLab metadata.' 'Creates or validates repository-root configuration, then applies the configured project description, topics, and labels.' './rivet.ps1 bootstrap -DryRun' -Interactions 'Exclusive. DryRun previews initialization and defers remote synchronization until configuration is applied.'
    New-HelpEntry 'Profile' 'string' 'existing profile or jsm' 'Select a repository makeup for initialization.' 'Loads profiles/<name>/profile.ps1 from the Rivet installation. Existing configurations without profile retain jsm behaviour. New profile folders need no router registration.' './rivet.ps1 init -Profile 11ty -DryRun' -Values '11ty, jsm, psm, or another installed profile.' -Interactions 'Init and bootstrap only; subsequent commands use repo_config.json.'
    New-HelpEntry 'Manifest' 'string' 'profile default' 'Select the repository-relative manifest during initialization.' 'For psm, specify a .psd1 path. A single root module manifest can be inferred; multiple candidates require an explicit path.' './rivet.ps1 init -Profile psm -Manifest src/MyModule.psd1 -DryRun' -Interactions 'Init and bootstrap only. Saved as psm.manifest by the psm profile.'
    New-HelpEntry 'Bun' 'switch' 'false' 'Include Bun runtime templates (bunfig.toml and bun.lock).' 'Used during init and bootstrap to populate Bun configuration while retaining package.json for scripts and package metadata.' './rivet.ps1 init -Bun -DryRun' -Interactions 'Applies to init and bootstrap workflows.'
    New-HelpEntry 'PrepRelease' 'switch' 'false' 'Prepare all standard release metadata.' 'Synchronizes profile manifests, README metadata and TOC, finalized changelog identity, release-notes.md, and mr.md. With Commit, only changed tracked release files are selected for review.' './rivet.ps1 prep-release -DryRun' -Interactions 'Implies FinalizeRelease and UpdateMergeRequest. Document and commit parameters remain available.'
    New-HelpEntry 'Doctor' 'switch' 'false' 'Validate rivet repository readiness.' 'Checks PowerShell, Git, configuration, required files, commit defaults, and optional GitLab credentials without changing repository state.' './rivet.ps1 doctor' -Interactions 'Missing optional GitLab credentials are warnings; required failures return an error.'
    New-HelpEntry 'Status' 'switch' 'false' 'Show repository and release state.' 'Displays branch, HEAD, upstream counts, worktree count, version baseline, calculated version, and next production and snapshot tags.' './rivet.ps1 status' -Interactions 'Read-only and exclusive.'
    New-HelpEntry 'VersionReport' 'switch' 'false' 'Explain the next version calculation.' 'Shows the stable tag baseline and classifies each subsequent commit as major, minor, patch, or no bump.' './rivet.ps1 version' -Interactions 'Read-only and exclusive.'
    New-HelpEntry 'ValidateReadme' 'switch' 'false' 'Validate required README headings.' 'Parses ATX headings outside fenced code, normalizes Markdown presentation, and prints a pass or missing result for every readme.requiredHeadings entry.' './rivet.ps1 readme' -Interactions 'Read-only and exclusive when selected directly. Default metadata runs also validate unless SkipReadmeValidation is set.'
    New-HelpEntry 'HelpParameter' 'string' 'unset' 'Select a detailed parameter manual page.' 'Passes a parameter name or alias to help.ps1. The Param alias supplies the command-style spelling.' './rivet.ps1 help -Param Commit' -Aliases @('Param') -Values 'Any run.ps1 parameter name or alias.' -Interactions 'Can be used with the help command or -Help. Using -Param help opens the overview.'
    New-HelpEntry 'SkipVersion' 'switch' 'false' 'Skip SemVer and manifest synchronization.' 'Prevents Conventional Commit scanning and leaves package.json and jsr.jsonc versions unchanged.' './rivet.ps1 -SkipVersion' -Interactions 'Does not disable header or TOC generation.'
    New-HelpEntry 'SkipReadmeMetadata' 'switch' 'false' 'Skip the generated README project header.' 'Leaves the leading centered README metadata block unchanged.' './rivet.ps1 -SkipReadmeMetadata' -Interactions 'Does not disable README table-of-contents generation.'
    New-HelpEntry 'SkipTableOfContents' 'switch' 'false' 'Skip README table-of-contents generation.' 'Leaves the marker-managed table of contents unchanged.' './rivet.ps1 -SkipTableOfContents' -Interactions 'Does not disable README header generation.'
    New-HelpEntry 'SkipReadmeValidation' 'switch' 'false' 'Skip required README heading validation.' 'Disables the configured README contract check during the default multi-action run.' './rivet.ps1 -SkipReadmeValidation' -Interactions 'Does not disable header or table-of-contents generation.'
    New-HelpEntry 'UpdateReleaseDocs' 'switch' 'false' 'Generate draft changelog and release notes.' 'Updates only rivet marker-bounded content using commits after the selected release baseline.' './rivet.ps1 -UpdateReleaseDocs -DryRun' -Interactions 'FromTag, ReleaseVersion, IncludeCommitHash, IncludeAuthor, and DryRun alter this action.'
    New-HelpEntry 'FinalizeRelease' 'switch' 'false' 'Generate finalized, dated release documentation.' 'Implies release-document generation and writes the result beneath the finalized version heading.' './rivet.ps1 -FinalizeRelease -ReleaseVersion 0.29.0' -Interactions 'ReleaseVersion can override the calculated package version.'
    New-HelpEntry 'RebuildChangelog' 'switch' 'false' 'Rebuild complete changelog from Git tag history.' 'Iterates across all reachable Git tags in chronological order and regenerates CHANGELOG.md and docs/data/changelog.json with conventional commit notes for every release.' './rivet.ps1 rebuild-changelog -DryRun' -Aliases @('Rebuild') -Interactions 'WriteChangelogJson, IncludeCommitHash, IncludeAuthor, and DryRun alter this action.'
    New-HelpEntry 'UpdateChangelogJson' 'switch' 'false' 'Generate complete documentation changelog data.' 'Writes docs/data/changelog.json from every version and note in canonical CHANGELOG.md, enriched with exact Git metadata when available. Unknown historical metadata remains null.' './rivet.ps1 -UpdateReleaseDocs -UpdateChangelogJson -DryRun' -Interactions 'Requires UpdateReleaseDocs, FinalizeRelease, or PrepRelease. CHANGELOG.md remains the canonical human-facing record.'
    New-HelpEntry 'UpdateMergeRequest' 'switch' 'false' 'Generate the working merge-request document.' 'Seeds mr.md when missing and updates its generated identity and change-list regions while preserving manual sections.' './rivet.ps1 -UpdateMergeRequest -MergeTargetBranch main' -Interactions 'FromTag, ReleaseVersion, MergeTargetBranch, IncludeCommitHash, IncludeAuthor, and DryRun alter this action.'
    New-HelpEntry 'CreateGitLabMergeRequest' 'switch' 'false' 'Create a GitLab merge request from mr.md.' 'Reads the title, source, target, and Markdown description from mr.md and rejects a duplicate open merge request.' './rivet.ps1 -UpdateMergeRequest -CreateGitLabMergeRequest -DryRun' -Interactions 'Requires the configured token. Mutually exclusive with UpdateGitLabMergeRequest.'
    New-HelpEntry 'UpdateGitLabMergeRequest' 'switch' 'false' 'Update the matching open GitLab merge request.' 'Finds one open merge request by source and target branch, then replaces its title and description from mr.md.' './rivet.ps1 -UpdateMergeRequest -UpdateGitLabMergeRequest -DryRun' -Interactions 'Requires the configured token. Mutually exclusive with CreateGitLabMergeRequest.'
    New-HelpEntry 'ReleaseVersion' 'string' 'calculated package version' 'Override the displayed release version.' 'Supplies an explicit SemVer identity to release and merge-request document generation.' './rivet.ps1 -FinalizeRelease -ReleaseVersion 0.29.0' -Values 'SemVer without a leading v, for example 0.29.0.' -Interactions 'Used only by requested release or merge-request actions.'
    New-HelpEntry 'FromTag' 'string' 'action-specific baseline' 'Select an explicit reachable Git baseline.' 'Overrides automatic range selection. Release documents normally use the latest reachable GitLab release; merge-request generation normally uses the latest stable tag.' './rivet.ps1 -UpdateReleaseDocs -FromTag v0.27.3' -Interactions 'The ref must resolve and be an ancestor of HEAD.'
    New-HelpEntry 'MergeTargetBranch' 'string' 'main' 'Set the merge-request target branch.' 'Controls the target branch written into generated mr.md metadata.' './rivet.ps1 -UpdateMergeRequest -MergeTargetBranch develop' -Interactions 'Used only with UpdateMergeRequest.'
    New-HelpEntry 'IncludeCommitHash' 'switch' 'true' 'Include linked short hashes in generated change lists.' 'Each short hash is a Markdown link to its GitLab commit; explicitly pass :$false to omit it.' './rivet.ps1 -UpdateReleaseDocs -IncludeCommitHash:$false' -Values '$true or $false.' -Interactions 'Affects release and merge-request document generation.'
    New-HelpEntry 'IncludeAuthor' 'switch' 'true' 'Include GitLab author mentions in generated change lists.' 'A valid username is emitted as @username for GitLab auto-linking; names containing spaces remain plain text.' './rivet.ps1 -UpdateReleaseDocs -IncludeAuthor:$false' -Values '$true or $false.' -Interactions 'Affects release and merge-request document generation.'
    New-HelpEntry 'SyncGitLabMetadata' 'switch' 'false' 'Synchronize configured GitLab project metadata.' 'Applies the configured description, topics, and managed project labels using the token environment variable.' './rivet.ps1 -SyncGitLabMetadata -DryRun' -Interactions 'Remote access requires GITLAB_API_KEY. DryRun suppresses writes.'
    New-HelpEntry 'DeleteMissingLabels' 'switch' 'false' 'Delete managed GitLab labels absent from config.' 'Expands synchronization to remove remote project labels not present in the authoritative catalog.' './rivet.ps1 -SyncGitLabMetadata -DeleteMissingLabels -DryRun' -Interactions 'Has effect only with SyncGitLabMetadata. Preview with DryRun first.'
    New-HelpEntry 'Commit' 'switch' 'false' 'Open the reviewed Conventional Commit workflow.' 'Selects type, exact scope, and files; previews the subject, extracted release note, totals, and patch before staging only reviewed paths.' './rivet.ps1 -Commit' -Interactions 'CommitType, CommitScope, CommitDescription, CommitFiles, and CommitAll control selection. DryRun never stages or commits.'
    New-HelpEntry 'CommitType' 'string' 'interactive configured default' 'Supply the Conventional Commit type.' 'Bypasses the type menu and validates the value against commit.types in repo_config.json.' './rivet.ps1 -Commit -CommitType feat' -Values 'Configured values such as feat, fix, docs, refactor, perf, test, build, ci, chore, or revert.' -Interactions 'Requires Commit to execute the workflow.'
    New-HelpEntry 'CommitScope' 'string' 'interactive configured default' 'Supply an exact Conventional Commit scope.' 'Suggests changed files using configured path patterns. The same value filters -glo, release documents, and merge-request changes by exact parsed scope.' './rivet.ps1 -glo -CommitScope core' -Values 'A configured scope or none.' -Interactions 'With Commit, none omits parentheses from the subject.'
    New-HelpEntry 'CommitDescription' 'string' 'interactive configured default' 'Supply the commit subject description.' 'Bypasses the description prompt. The final Conventional Commit subject is limited to 100 characters and trailing periods are removed.' "./rivet.ps1 -Commit -CommitDescription 'add repository manual'" -Values 'One non-empty line.' -Interactions 'Requires Commit to execute the workflow.'
    New-HelpEntry 'CommitFiles' 'string array' 'interactive selection' 'Stage only explicitly selected changed paths.' 'The review shows their diff and leaves every unselected change untouched.' "./rivet.ps1 -Commit -CommitFiles 'src/core.js','tests/core.test.js'" -Values 'Changed repository-relative paths.' -Interactions 'Requires Commit and cannot be combined with CommitAll.'
    New-HelpEntry 'CommitAll' 'switch' 'false' 'Select every changed path for the commit.' 'Bypasses file selection but still previews the complete selection and requires confirmation.' './rivet.ps1 -Commit -CommitAll -DryRun' -Interactions 'Requires Commit and cannot be combined with CommitFiles.'
    New-HelpEntry 'Tag' 'switch' 'false' 'Review, create, and push a release tag.' 'Runs as an exclusive action. It calculates the version, rejects a behind or diverged branch, pushes locally ahead commits first, then creates and pushes one annotated tag.' './rivet.ps1 -Tag -DryRun' -Interactions 'Production tags trigger CI publishing and release jobs. DryRun performs no branch, tag, or remote writes.'
    New-HelpEntry 'Snapshot' 'switch' 'false' 'Create a plain SemVer snapshot tag.' 'Creates a tag such as v0.28.0. CI runs validation but omits package publishing and production release jobs; production tags append the configured -release suffix.' './rivet.ps1 -Tag -Snapshot -DryRun' -Interactions 'Requires Tag. Without Snapshot, Tag creates a production tag such as v0.28.0-release.'
    New-HelpEntry 'TagForce' 'switch' 'false' 'Allow non-interactive tag publication.' 'Bypasses only the final keyboard confirmation; all worktree, upstream, manifest, duplicate-tag, and remote checks remain enforced.' './rivet.ps1 -Tag -Snapshot -TagForce' -Interactions 'Requires Tag. Intended for reviewed CI or scripted automation.'
    New-HelpEntry 'TagVersion' 'string' 'calculated next version' 'Override the version used for a tag.' 'Accepts a stable MAJOR.MINOR.PATCH value with an optional leading v. Prefix and production release suffix formatting remain configuration-driven.' './rivet.ps1 -Tag -TagVersion 0.29.0 -DryRun' -Values 'MAJOR.MINOR.PATCH or vMAJOR.MINOR.PATCH.' -Interactions 'Requires Tag. Manifest versions must match before an applied tag can be created.'
    New-HelpEntry 'GitLog' 'switch' 'false' 'Open the exclusive detailed Git history view.' 'Prints repository state, enriched one-line commits, aggregate history details, and changed paths, then exits without running metadata actions.' './rivet.ps1 -glo' -Aliases @('glo') -Interactions 'GitLogCount, GitLogAll, and GitLogNoMerges alter this view.'
    New-HelpEntry 'GitLogCount' 'integer' '25' 'Set the maximum displayed commit count.' 'Limits the number of commits parsed, rendered, and included in aggregate history totals.' './rivet.ps1 -glo -GitLogCount 75' -Values '1 through 500.' -Interactions 'Used only by GitLog/glo.'
    New-HelpEntry 'GitLogAll' 'switch' 'false' 'Read history from every Git ref.' 'Adds git log --all so commits reachable from all local and remote refs can be displayed.' './rivet.ps1 -glo -GitLogAll' -Interactions 'Used only by GitLog/glo.'
    New-HelpEntry 'GitLogNoMerges' 'switch' 'false' 'Omit merge commits from history.' 'Adds git log --no-merges before parsing the detailed history.' './rivet.ps1 -glo -GitLogNoMerges' -Interactions 'Used only by GitLog/glo.'
    New-HelpEntry 'RepositoryRoot' 'string' 'current directory' 'Select the consuming repository root.' 'Separates repository operations from the standalone rivet checkout. rivet.ps1 supplies this value automatically.' './rivet/run.ps1 -RepositoryRoot $PWD status' -Values 'A path inside a Git working tree.' -Interactions 'Normally omitted when invoking rivet.ps1.'
    New-HelpEntry 'ConfigPath' 'string' 'repository-root repo_config.json' 'Override repository configuration discovery.' 'Supplies an explicit configuration path while the consuming repository root continues to be resolved through Git.' './rivet.ps1 doctor -ConfigPath ./config/repo_config.json' -Values 'An existing JSON configuration path.' -Interactions 'Initialization honors this path for repo_config.json; other managed files use normal discovery.'
    New-HelpEntry 'FlowGraph' 'switch' 'false' 'Render the interactive ASCII flow graph of Rivet lifecycle.' 'Renders a visual Flowgraph diagram illustrating the complete Rivet automation pipeline: Git worktree discovery, doctor diagnostics, SemVer calculation, manifest synchronization, release documentation, merge request management, scoped commit reviews, tag validation, and GitLab publication.' './rivet.ps1 flow' -Aliases @('Flow', 'Pipeline') -Interactions 'Read-only and exclusive. Supports Pipeline and TopDown layout algorithms.'
    New-HelpEntry 'WorkItems' 'switch' 'false' 'Manage local work items and GitLab issues.' 'Lists, pulls, pushes, or scaffolds local work item markdown files formatted like mr.md in .rivet/work-items/ and connects to GitLab Issues API with caching.' './rivet.ps1 work-items' -Aliases @('Issues', 'SyncWorkItems', 'PullIssues', 'PushIssues', 'ListIssues', 'NewIssue', 'Template') -Interactions 'Supports -PullIssues, -PushIssues, -ListIssues, -NewIssue, -IssueIid, -IssueTitle, -IssueDescription, -IssueLabels, -IssueState, -ForceRefresh.'
    New-HelpEntry 'IssueIid' 'integer' '0' 'Target a specific GitLab issue IID for pull or push.' 'When provided with Pull, downloads only that specific issue. When provided with Template, sets the issue IID in the metadata table.' './rivet.ps1 work-items -PullIssues -Iid 42' -Aliases @('Iid') -Interactions 'Used with WorkItems, PullIssues, or Template.'
    New-HelpEntry 'ForceRefresh' 'switch' 'false' 'Bypass the Rivet API cache when fetching remote issues.' 'Forces a live network request to GitLab REST API and updates the local cache.' './rivet.ps1 work-items -PullIssues -ForceRefresh' -Interactions 'Used with WorkItems and PullIssues.'
    New-HelpEntry 'Raw' 'switch' 'false' 'Suppress visual TUI report cards and return structured objects.' 'Allows individual inner actions to run silently within compound [MA] workflows while returning rich execution metadata.' './rivet.ps1 prep-release -Raw' -Interactions 'Used programmatically or in scripted pipelines.'
    New-HelpEntry 'DryRun' 'switch' 'false' 'Preview supported actions without applying writes.' 'Passes preview mode into manifest, README, documentation, GitLab, and commit actions. Git history mode is always read-only.' './rivet.ps1 -DryRun' -Interactions 'Use with destructive or remote options before applying changes.'
)

function Get-HelpGroup {
    param([Parameter(Mandatory)][string]$Name)
    switch -Regex ($Name) {
        '^(Command|Help|Menu|Init|Bootstrap|Bun|Profile|Manifest|HelpParameter|Doctor|Status|VersionReport|ValidateReadme|FlowGraph|Flow|Pipeline|WorkItems|Issues|SyncWorkItems|PullIssues|PushIssues|ListIssues|NewIssue|Template|IssueIid|Iid|ForceRefresh|Raw|RepositoryRoot|ConfigPath|DryRun)$' { return 'HELP AND EXECUTION' }
        '^(SkipVersion|SkipReadmeMetadata|SkipTableOfContents|SkipReadmeValidation)$' { return 'LOCAL METADATA' }
        '^(PrepRelease|UpdateReleaseDocs|FinalizeRelease|RebuildChangelog|Rebuild|UpdateChangelogJson|UpdateMergeRequest|CreateGitLabMergeRequest|UpdateGitLabMergeRequest|ReleaseVersion|FromTag|MergeTargetBranch|IncludeCommitHash|IncludeAuthor)$' { return 'RELEASE AND MERGE REQUEST' }
        '^(SyncGitLabMetadata|DeleteMissingLabels)$' { return 'GITLAB METADATA' }
        '^(Commit|CommitType|CommitScope|CommitDescription|CommitFiles|CommitAll)$' { return 'CONVENTIONAL COMMIT' }
        '^(Tag|Snapshot|TagForce|TagVersion)$' { return 'TAGGING AND PUBLISHING' }
        '^(GitLog|GitLogCount|GitLogAll|GitLogNoMerges)$' { return 'GIT HISTORY' }
        default { return 'OTHER' }
    }
}

$bannerTokens = ConvertTo-AsciiTokens -Lines ($asciiBanner -split '\r?\n') -Connectivity 8
foreach ($line in @(ConvertTo-GradientAsciiLines -TokenObject $bannerTokens -Mode Horizontal -StartColor @(0, 180, 255) -EndColor @(255, 60, 180))) { [Console]::WriteLine($line) }
[Console]::WriteLine('')

function Write-ManualField([string]$Label, [string]$Value) {
    [Console]::WriteLine("$(Format-AnsiText -Text $Label.PadRight(14) -Color @(145, 155, 175))$Value")
}

if (-not [string]::IsNullOrWhiteSpace($Param)) {
    $lookup = $Param.TrimStart('-')
    $entry = $entries | Where-Object { $_.Name -ieq $lookup -or $_.Aliases -icontains $lookup } | Select-Object -First 1
    if ($null -eq $entry) {
        $names = ($entries.Name | Sort-Object) -join ', '
        throw "Unknown run.ps1 parameter '$Param'. Available parameters: $names"
    }
    [Console]::WriteLine((Format-AnsiText -Text "-$($entry.Name)" -Color @(0, 200, 255) -Bold))
    [Console]::WriteLine((Format-AnsiText -Text $entry.Summary -Color @(220, 225, 235) -Bold))
    [Console]::WriteLine('')
    Write-ManualField 'GROUP' (Get-HelpGroup -Name $entry.Name)
    Write-ManualField 'TYPE' $entry.Type
    Write-ManualField 'DEFAULT' $entry.Default
    Write-ManualField 'ALIASES' $(if ($entry.Aliases.Count) { ($entry.Aliases -join ', ') } else { 'none' })
    Write-ManualField 'VALUES' $entry.Values
    [Console]::WriteLine('')
    [Console]::WriteLine((Format-AnsiText -Text 'DETAIL' -Color @(210, 120, 255) -Bold))
    [Console]::WriteLine($entry.Details)
    [Console]::WriteLine('')
    [Console]::WriteLine((Format-AnsiText -Text 'INTERACTIONS' -Color @(210, 120, 255) -Bold))
    [Console]::WriteLine($entry.Interactions)
    [Console]::WriteLine('')
    [Console]::WriteLine((Format-AnsiText -Text 'EXAMPLE' -Color @(80, 220, 150) -Bold))
    [Console]::WriteLine("  $($entry.Example)")
    return
}

[Console]::WriteLine((Format-AnsiText -Text 'RIVET MANUAL' -Color @(0, 200, 255) -Bold))
[Console]::WriteLine('Repository-local JavaScript metadata, release, GitLab, commit, and history automation.')
[Console]::WriteLine('')
Write-ManualField 'RUN' './rivet.ps1 [parameters]'
Write-ManualField 'HELP' './rivet.ps1 help [parameter]'
Write-ManualField 'MENU' './rivet.ps1 menu'
Write-ManualField 'PARAM HELP' './rivet/help.ps1 -Param <name>'
Write-ManualField 'HISTORY' './rivet.ps1 -glo'
Write-ManualField 'COMMIT' './rivet.ps1 -Commit'
[Console]::WriteLine('')
[Console]::WriteLine((Format-AnsiText -Text 'PARAMETER GROUPS' -Color @(210, 120, 255) -Bold))
$groupOrder = @('HELP AND EXECUTION', 'LOCAL METADATA', 'RELEASE AND MERGE REQUEST', 'GITLAB METADATA', 'CONVENTIONAL COMMIT', 'TAGGING AND PUBLISHING', 'GIT HISTORY', 'OTHER')
foreach ($group in $groupOrder) {
    $groupEntries = @($entries | Where-Object { (Get-HelpGroup -Name $_.Name) -eq $group })
    if ($groupEntries.Count -eq 0) { continue }
    [Console]::WriteLine('')
    [Console]::WriteLine((Format-AnsiText -Text "  $group" -Color @(0, 200, 255) -Bold))
    foreach ($entry in $groupEntries) {
        $aliasText = if ($entry.Aliases.Count) { " / -$($entry.Aliases -join ', -')" } else { '' }
        $name = "-$($entry.Name)$aliasText"
        [Console]::WriteLine("    $(Format-AnsiText -Text $name.PadRight(30) -Color @(255, 195, 75))$($entry.Summary)")
    }
}
[Console]::WriteLine('')
[Console]::WriteLine((Format-AnsiText -Text 'EXAMPLES' -Color @(210, 120, 255) -Bold))
$examples = @(
    [pscustomobject]@{ Title = 'Preview repository configuration initialization'; Command = './rivet.ps1 init -DryRun' }
    [pscustomobject]@{ Title = 'Preview repository and GitLab bootstrap'; Command = './rivet.ps1 bootstrap -DryRun' }
    [pscustomobject]@{ Title = 'Preview complete release preparation'; Command = './rivet.ps1 prep-release -DryRun' }
    [pscustomobject]@{ Title = 'Validate required README sections'; Command = './rivet.ps1 readme' }
    [pscustomobject]@{ Title = 'Open the interactive rivet command center'; Command = './rivet.ps1 menu' }
    [pscustomobject]@{ Title = 'Validate local rivet readiness'; Command = './rivet.ps1 doctor' }
    [pscustomobject]@{ Title = 'Show repository and release state'; Command = './rivet.ps1 status' }
    [pscustomobject]@{ Title = 'Explain the calculated version'; Command = './rivet.ps1 version' }
    [pscustomobject]@{ Title = 'Preview all default local metadata actions'; Command = './rivet.ps1 -DryRun' }
    [pscustomobject]@{ Title = 'Apply the default local metadata actions'; Command = './rivet.ps1' }
    [pscustomobject]@{ Title = 'Generate draft release documents from an explicit tag'; Command = './rivet.ps1 -UpdateReleaseDocs -FromTag v0.27.3' }
    [pscustomobject]@{ Title = 'Finalize release documentation with an explicit version'; Command = './rivet.ps1 -FinalizeRelease -ReleaseVersion 0.29.0' }
    [pscustomobject]@{ Title = 'Generate the merge-request working document'; Command = './rivet.ps1 -UpdateMergeRequest -MergeTargetBranch main' }
    [pscustomobject]@{ Title = 'Preview creating a GitLab merge request from mr.md'; Command = './rivet.ps1 -UpdateMergeRequest -CreateGitLabMergeRequest -DryRun' }
    [pscustomobject]@{ Title = 'Preview updating the matching GitLab merge request'; Command = './rivet.ps1 -UpdateMergeRequest -UpdateGitLabMergeRequest -DryRun' }
    [pscustomobject]@{ Title = 'Preview GitLab metadata synchronization and label deletion'; Command = './rivet.ps1 -SyncGitLabMetadata -DeleteMissingLabels -DryRun' }
    [pscustomobject]@{ Title = 'Open the interactive Conventional Commit workflow'; Command = './rivet.ps1 -Commit' }
    [pscustomobject]@{ Title = 'Preview a commit with non-interactive values'; Command = "./rivet.ps1 -Commit -CommitType feat -CommitScope rivet -CommitDescription 'add repository automation' -DryRun" }
    [pscustomobject]@{ Title = 'Preview a snapshot checkpoint tag ignored by CI'; Command = './rivet.ps1 -Tag -Snapshot -DryRun' }
    [pscustomobject]@{ Title = 'Preview a production publishing tag'; Command = './rivet.ps1 -Tag -TagVersion 0.29.0 -DryRun' }
    [pscustomobject]@{ Title = 'Show 50 detailed commits across all refs'; Command = './rivet.ps1 -glo -GitLogCount 50 -GitLogAll' }
    [pscustomobject]@{ Title = 'Open detailed help for one parameter or alias'; Command = './rivet.ps1 help glo' }
)
foreach ($example in $examples) {
    [Console]::WriteLine('')
    [Console]::WriteLine("  $(Format-AnsiText -Text $example.Title -Color @(220, 225, 235) -Bold)")
    [Console]::WriteLine("    $(Format-AnsiText -Text $example.Command -Color @(80, 220, 150))")
}
[Console]::WriteLine('')
[Console]::WriteLine((Format-AnsiText -Text "Use -Param for full behavior, constraints, interactions, and an example." -Color @(145, 155, 175)))
