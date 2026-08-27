<#
.SYNOPSIS
    Manages and synchronizes local work items, GitLab issues, and the aggregated tasklist dashboard.
.DESCRIPTION
    Stores local work items as structured Markdown files under .rivet/work-items/.
    Features table-based metadata matching the mr.md layout with bidirectional sync:
    - Pull: Downloads specific or modified remote issues and discussion notes into local work items.
    - Push: Creates or updates remote GitLab issues from local markdown files marked with 'Sync Action: push'.
    - List / Tasks: Renders a dense ASCII TUI summary table of active, draft, and closed work items.
    - View: Displays full work item details (metadata table, description, acceptance criteria, notes).
    - Close / Reopen: Mutates work item state, flags for push sync, and regenerates task dashboard.
    - New / Template: Scaffolds a new local work item template formatted with metadata tables.
    - GenerateList: Rebuilds the aggregated .rivet/workitems-list.md dashboard index.
.PARAMETER RepositoryRoot
    Path to the repository root directory.
.PARAMETER Config
    Rivet configuration object. If omitted, loaded automatically.
.PARAMETER Action
    Workflow operation: 'List' (default), 'Pull', 'Push', 'New', 'Template', 'Sync', 'View', 'Close', 'Reopen', 'GenerateList'.
.PARAMETER Iid
    Specific GitLab Issue IID to target for pull, push, view, close, reopen, or template scaffolding.
.PARAMETER Title
    Title for new work item creation or search target.
.PARAMETER Description
    Description or body for new work item.
.PARAMETER Labels
    Array of label names to assign.
.PARAMETER Milestone
    Milestone title to associate with the work item.
.PARAMETER State
    Issue state filter or target ('opened', 'closed', or 'all'). Default: 'opened'.
.PARAMETER ForceRefresh
    Bypasses the Rivet API cache when fetching remote issues.
.PARAMETER DryRun
    Executes without writing remote API updates or local files.
.PARAMETER Raw
    Suppresses console reporting and returns structured output objects.
#>
function Sync-RivetWorkItems {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, Position = 0)][string]$RepositoryRoot,
        [Parameter()][object]$Config,
        [Parameter(Position = 1)]
        [ValidateSet('List', 'Pull', 'Push', 'New', 'Template', 'Sync', 'View', 'Close', 'Reopen', 'GenerateList')]
        [string]$Action = 'List',
        [Parameter()][int]$Iid = 0,
        [Parameter()][string]$Title = '',
        [Parameter()][string]$Description = '',
        [Parameter()][string[]]$Labels = @(),
        [Parameter()][string]$Milestone = '',
        [Parameter()][ValidateSet('opened', 'closed', 'all')][string]$State = 'opened',
        [Parameter()][switch]$ForceRefresh,
        [switch]$DryRun,
        [switch]$Raw
    )

    Set-StrictMode -Version Latest
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $repoPath = [System.IO.Path]::GetFullPath($RepositoryRoot)
    $workItemsDir = [System.IO.Path]::Combine($repoPath, '.rivet', 'work-items')
    $cacheDir = [System.IO.Path]::Combine($repoPath, '.rivet', 'cache')

    if (-not [System.IO.Directory]::Exists($workItemsDir) -and -not $DryRun) {
        [System.IO.Directory]::CreateDirectory($workItemsDir) | Out-Null
    }

    # Initialize cache subsystem
    if (Get-Command -Name 'Initialize-RivetCache' -CommandType Function -ErrorAction SilentlyContinue) {
        Initialize-RivetCache -CacheDirectory $cacheDir -DefaultTtlSeconds 1800
    }

    if ($null -eq $Config) {
        $configPath = Resolve-RivetPath -RepositoryRoot $repoPath -ItemName 'repo_config.json'
        if ([System.IO.File]::Exists($configPath)) {
            try { $Config = Get-RivetConfiguration -ConfigPath $configPath } catch {}
        }
    }

    $cDim    = "`e[38;2;120;130;145m"
    $cBold   = "`e[1m"
    $cReset  = "`e[0m"
    $cOrange = "`e[38;2;255;130;0m"
    $cGreen  = "`e[38;2;80;220;150m"
    $cRed    = "`e[38;2;255;90;105m"
    $cYellow = "`e[38;2;255;195;75m"
    $cCyan   = "`e[38;2;0;200;255m"
    $cWhite  = "`e[38;2;230;235;245m"

    function ConvertFrom-WorkItemMarkdown {
        param([string]$FilePath)
        $content = [System.IO.File]::ReadAllText($FilePath)
        $meta = [ordered]@{
            File          = $FilePath
            FileName      = [System.IO.Path]::GetFileName($FilePath)
            Iid           = $null
            Title         = ''
            SyncAction    = 'pull'
            State         = 'opened'
            Labels        = @()
            Milestone     = ''
            Author        = ''
            WebUrl        = ''
            CreatedAt     = ''
            UpdatedAt     = ''
            Description   = ''
            RecentComment = $null
        }

        # 1. Check for YAML frontmatter
        if ($content -match '(?ms)^\s*---\r?\n(.*?)\r?\n---\r?\n(.*)$') {
            $frontmatter = $Matches[1]
            $meta.Description = $Matches[2].Trim()
            foreach ($line in ($frontmatter -split '\r?\n')) {
                if ($line -match '^\s*iid:\s*(\d+)\s*$') { $meta.Iid = [int]$Matches[1] }
                elseif ($line -match '^\s*title:\s*["'']?(.*?)["'']?\s*$') { $meta.Title = $Matches[1].Trim() }
                elseif ($line -match '^\s*sync:\s*["'']?(.*?)["'']?\s*$') { $meta.SyncAction = $Matches[1].Trim().ToLower() }
                elseif ($line -match '^\s*state:\s*["'']?(.*?)["'']?\s*$') { $meta.State = $Matches[1].Trim().ToLower() }
                elseif ($line -match '^\s*labels:\s*\[(.*?)\]\s*$') {
                    $meta.Labels = @(($Matches[1] -split ',') | ForEach-Object { $_.Trim().Trim('"').Trim("'") } | Where-Object { $_ })
                }
                elseif ($line -match '^\s*milestone:\s*["'']?(.*?)["'']?\s*$') { $meta.Milestone = $Matches[1].Trim() }
                elseif ($line -match '^\s*author:\s*["'']?(.*?)["'']?\s*$') { $meta.Author = $Matches[1].Trim() }
                elseif ($line -match '^\s*web_url:\s*["'']?(.*?)["'']?\s*$') { $meta.WebUrl = $Matches[1].Trim() }
                elseif ($line -match '^\s*created_at:\s*["'']?(.*?)["'']?\s*$') { $meta.CreatedAt = $Matches[1].Trim() }
                elseif ($line -match '^\s*updated_at:\s*["'']?(.*?)["'']?\s*$') { $meta.UpdatedAt = $Matches[1].Trim() }
            }
            return [pscustomobject]$meta
        }

        # 2. Check for Table-based mr.md style format
        foreach ($line in ($content -split '\r?\n')) {
            if ($line -match '\|\s*\*\*Gitlab Issue IID:\*\*\s*\|\s*`?(\d+)`?\s*\|') { $meta.Iid = [int]$Matches[1] }
            elseif ($line -match '\|\s*\*\*Gitlab Issue Link:\*\*\s*\|\s*`?(.*?)`?\s*\|') {
                $val = $Matches[1].Trim().Trim('`')
                if ($val -ine 'link-here' -and $val -ine 'link here') { $meta.WebUrl = $val }
            }
            elseif ($line -match '\|\s*\*\*Sync Action:\*\*\s*\|\s*`?(.*?)`?\s*\|') {
                $val = $Matches[1].Trim().Trim('`').ToLower()
                if ($val) { $meta.SyncAction = $val }
            }
            elseif ($line -match '\|\s*\*\*Status:\*\*\s*\|\s*`?(.*?)`?\s*\|') {
                $val = $Matches[1].Trim().Trim('`').ToLower()
                if ($val) { $meta.State = $val }
            }
            elseif ($line -match '\|\s*\*\*Created Date:\*\*\s*\|\s*`?(.*?)`?\s*\|') {
                $val = $Matches[1].Trim().Trim('`')
                if ($val -ine 'date-here') { $meta.CreatedAt = $val }
            }
            elseif ($line -match '\|\s*\*\*Last Updated Date:\*\*\s*\|\s*`?(.*?)`?\s*\|') {
                $val = $Matches[1].Trim().Trim('`')
                if ($val -ine 'date-here') { $meta.UpdatedAt = $val }
            }
            elseif ($line -match '\|\s*\*\*Author:\*\*\s*\|\s*`?(.*?)`?\s*\|') {
                $val = $Matches[1].Trim().Trim('`')
                if ($val -ine 'author-here') { $meta.Author = $val }
            }
            elseif ($line -match '\|\s*\*\*Milestone:\*\*\s*\|\s*`?(.*?)`?\s*\|') {
                $val = $Matches[1].Trim().Trim('`')
                if ($val -ine 'milestone-here') { $meta.Milestone = $val }
            }
            elseif ($line -match '\|\s*\*\*Labels:\*\*\s*\|\s*`?(.*?)`?\s*\|') {
                $val = $Matches[1].Trim().Trim('`')
                if ($val -ine 'labels-here') {
                    $meta.Labels = @(($val -split ',') | ForEach-Object { $_.Trim().Trim('"').Trim("'") } | Where-Object { $_ })
                }
            }
            elseif ($line -match '\|\s*Title:\s*\|\s*`?(.*?)`?\s*\|') {
                $val = $Matches[1].Trim().Trim('`')
                if ($val -ine 'Work Item Title' -and $val -ine 'Issue Title Here') { $meta.Title = $val }
            }
        }

        # Extract description / body below the title separator
        if ($content -match '(?ms)\|\s*Title:\s*\|\s*`?(.*?)`?\s*\|\r?\n(.*)$') {
            if (-not $meta.Title) {
                $matchedTitle = $Matches[1].Trim().Trim('`')
                if ($matchedTitle -ine 'Work Item Title') { $meta.Title = $matchedTitle }
            }
            $meta.Description = $Matches[2].Trim()
        } else {
            $meta.Description = $content.Trim()
            if (-not $meta.Title) {
                $meta.Title = [System.IO.Path]::GetFileNameWithoutExtension($FilePath)
            }
        }

        return [pscustomobject]$meta
    }

    function ConvertTo-WorkItemMarkdown {
        param([pscustomobject]$Item)
        $iidStr = if ($null -ne $Item.Iid -and $Item.Iid -gt 0) { "$($Item.Iid)" } else { 'id-here' }
        $linkStr = if ($Item.WebUrl) { "$($Item.WebUrl)" } else { 'link-here' }
        $syncAction = if ($Item.SyncAction) { $Item.SyncAction.ToLower() } else { 'pull' }
        $statusStr = if ($Item.State) { $Item.State.ToLower() } else { 'opened' }
        $createdStr = if ($Item.CreatedAt) { "$($Item.CreatedAt)" } else { (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') }
        $updatedStr = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
        $authorStr = if ($Item.Author) { "$($Item.Author)" } else { 'author-here' }
        $milestoneStr = if ($Item.Milestone) { "$($Item.Milestone)" } else { 'milestone-here' }
        $labelsStr = if ($Item.Labels -and @($Item.Labels).Count -gt 0) { ($Item.Labels -join ', ') } else { 'labels-here' }
        $titleStr = if ($Item.Title) { $Item.Title -replace '[`"\\]', '' } else { 'Work Item Title' }

        $desc = if ($Item.Description) {
            $Item.Description
        } else {
            "## **Description**`n`nProvide detailed problem specification or feature requirements here.`n`n## **Acceptance Criteria**`n`n- [ ] Clear testable criteria 1`n- [ ] Clear testable criteria 2`n`n## **Technical Notes**`n`n- Implementation details, architectural decisions, or related MR links."
        }

        $sb = [System.Text.StringBuilder]::new()
        [void]$sb.AppendLine('# Rivet Work Item')
        [void]$sb.AppendLine('')
        [void]$sb.AppendLine('Rivet Work Item Template `Version 1`')
        [void]$sb.AppendLine('')
        [void]$sb.AppendLine('|                                |                  |')
        [void]$sb.AppendLine('| ------------------------------ | ---------------- |')
        [void]$sb.AppendLine(('| **Gitlab Issue IID:**          | `{0}`        |' -f $iidStr))
        [void]$sb.AppendLine(('| **Gitlab Issue Link:**         | `{0}`       |' -f $linkStr))
        [void]$sb.AppendLine(('| **Sync Action:**               | `{0}`    |' -f $syncAction))
        [void]$sb.AppendLine(('| **Status:**                    | `{0}`     |' -f $statusStr))
        [void]$sb.AppendLine(('| **Created Date:**              | `{0}`    |' -f $createdStr))
        [void]$sb.AppendLine(('| **Last Updated Date:**         | `{0}`    |' -f $updatedStr))
        [void]$sb.AppendLine(('| **Author:**                    | `{0}`     |' -f $authorStr))
        [void]$sb.AppendLine(('| **Milestone:**                 | `{0}`  |' -f $milestoneStr))
        [void]$sb.AppendLine(('| **Labels:**                    | `{0}`     |' -f $labelsStr))
        [void]$sb.AppendLine('')
        [void]$sb.AppendLine('> [!Note]')
        [void]$sb.AppendLine('> Set `Sync Action:` to `pull` to refresh this issue from GitLab, or `push` to publish local changes to GitLab.')
        [void]$sb.AppendLine('')
        [void]$sb.AppendLine('---')
        [void]$sb.AppendLine('')
        [void]$sb.AppendLine('|        |                   |')
        [void]$sb.AppendLine('| ------ | ----------------- |')
        [void]$sb.AppendLine(('| Title: | `{0}` |' -f $titleStr))
        [void]$sb.AppendLine('')
        [void]$sb.AppendLine($desc)

        return $sb.ToString()
    }

    function Update-RivetWorkItemsListFile {
        param([object[]]$Items)

        $listFilePath = Resolve-RivetPath -RepositoryRoot $repoPath -ItemName 'workitems-list.md'
        $templatePath = [System.IO.Path]::Combine($PSScriptRoot, '..', 'templates', 'workitems-list.md')
        if (-not [System.IO.File]::Exists($templatePath)) {
            $templatePath = [System.IO.Path]::Combine($repoPath, 'templates', 'workitems-list.md')
        }

        $existingHeader = if ([System.IO.File]::Exists($listFilePath)) {
            [System.IO.File]::ReadAllText($listFilePath)
        } elseif ([System.IO.File]::Exists($templatePath)) {
            [System.IO.File]::ReadAllText($templatePath)
        } else {
            "# Rivet Task Tracker`n`n> [!NOTE]`n> Use the Rivet CLI (./rivet.ps1 work-items) to manage and synchronize work items.`n`n## **Tasklist**`n`n<!--rivet: generated Tasklist-->`n<!--rivet: generated Tasklist-->`n"
        }

        # Build task list markdown
        $sbTasks = [System.Text.StringBuilder]::new()
        
        # Sort items: opened first (by UpdatedAt desc), then closed
        $sorted = @($Items | Sort-Object -Property @{
            Expression = { if ($_.State -ieq 'opened') { 0 } else { 1 } }
        }, @{
            Expression = { $_.UpdatedAt }
            Descending = $true
        })

        foreach ($it in $sorted) {
            $statusIcon = if ($it.State -ieq 'opened') { '🟢 open' } else { '✅ closed' }
            $iidText = if ($it.Iid) { "#$($it.Iid)" } else { 'DRAFT' }
            $linkUrl = if ($it.WebUrl) { $it.WebUrl } else { "#$($it.Iid)" }
            $upDate = if ($it.UpdatedAt) { $it.UpdatedAt } else { (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') }
            $authorText = if ($it.Author) { "@$($it.Author -replace '^@','')" } else { 'unassigned' }
            $labelsText = if ($it.Labels -and @($it.Labels).Count -gt 0) {
                ($it.Labels | ForEach-Object { "`"$_`"" }) -join ', '
            } else { 'none' }

            [void]$sbTasks.AppendLine("### 🎯 **$($it.Title)**")
            [void]$sbTasks.AppendLine('')
            [void]$sbTasks.AppendLine("> _**Task Meta:**_ [$iidText]($linkUrl) &nbsp;|&nbsp; _**Last Updated:**_ ``$upDate`` \")
            [void]$sbTasks.AppendLine("> _**Assigned to:**_ $authorText \")
            [void]$sbTasks.AppendLine("> _**Labels:**_ ``$labelsText`` \")
            [void]$sbTasks.AppendLine("> _**Status:**_ $statusIcon")
            [void]$sbTasks.AppendLine('')

            # Summary from Description
            $summary = if ($it.Description) {
                $firstPara = ($it.Description -split '\r?\n\r?\n')[0]
                $firstPara.Trim()
            } else {
                'Individual task specifications and acceptance criteria managed in `.rivet/work-items/`.'
            }
            [void]$sbTasks.AppendLine($summary)
            [void]$sbTasks.AppendLine('')

            # Recent comment if present
            if ($it.PSObject.Properties['RecentComment'] -and $it.RecentComment) {
                $rc = $it.RecentComment
                [void]$sbTasks.AppendLine('#### **LAST MOST RECENT COMMENT**')
                [void]$sbTasks.AppendLine('')
                [void]$sbTasks.AppendLine("> > **@$($rc.Author)** _($($rc.CreatedAt))_: \")
                [void]$sbTasks.AppendLine("> > $($rc.Body)")
                [void]$sbTasks.AppendLine('')
            }
        }

        $generatedContent = $sbTasks.ToString().TrimEnd()

        $marker = '<!--rivet: generated Tasklist-->'
        $newFullContent = ''
        if ($existingHeader -match "(?ms)^(.*$marker\r?\n).*?(\r?\n$marker.*)$") {
            $newFullContent = "$($Matches[1])`n$generatedContent`n$($Matches[2])"
        } else {
            # Append generated section
            $newFullContent = "$existingHeader`n`n## **Tasklist**`n`n$marker`n`n$generatedContent`n`n$marker`n"
        }

        if (-not $DryRun) {
            $dir = [System.IO.Path]::GetDirectoryName($listFilePath)
            if (-not [System.IO.Directory]::Exists($dir)) { [System.IO.Directory]::CreateDirectory($dir) | Out-Null }
            [System.IO.File]::WriteAllText($listFilePath, $newFullContent, [System.Text.UTF8Encoding]::new($false))
        }

        return $listFilePath
    }

    $rows = [System.Collections.Generic.List[hashtable]]::new()
    $artifacts = [System.Collections.Generic.List[string]]::new()
    $localItems = [System.Collections.Generic.List[object]]::new()

    if ([System.IO.Directory]::Exists($workItemsDir)) {
        foreach ($file in [System.IO.Directory]::GetFiles($workItemsDir, '*.md')) {
            $localItems.Add((ConvertFrom-WorkItemMarkdown -FilePath $file))
        }
    }

    $token = if ($env:GITLAB_TOKEN) { $env:GITLAB_TOKEN }
             elseif ($env:GITLAB_API_KEY) { $env:GITLAB_API_KEY }
             elseif ($env:CI_JOB_TOKEN) { $env:CI_JOB_TOKEN }
             else { '' }
    $apiAvailable = ($null -ne $Config -and $Config.gitlab -and $Config.gitlab.baseUri -and $Config.project.path -and $token)

    switch ($Action) {
        { $_ -in @('New', 'Template') } {
            if ([string]::IsNullOrWhiteSpace($Title)) {
                $Title = if ($Iid -gt 0) { "Work Item $Iid" } else { 'New work item' }
            }
            $slug = ($Title.ToLower() -replace '[^a-z0-9]+', '-').Trim('-')
            if ([string]::IsNullOrWhiteSpace($slug)) { $slug = 'work-item' }
            $prefix = if ($Iid -gt 0) { "{0:D3}-" -f $Iid } else { 'draft-' }
            $fileName = "$prefix$slug.md"
            $targetFile = [System.IO.Path]::Combine($workItemsDir, $fileName)

            $newItem = [pscustomobject]@{
                File        = $targetFile
                FileName    = $fileName
                Iid         = if ($Iid -gt 0) { $Iid } else { $null }
                Title       = $Title
                SyncAction  = 'pull'
                State       = 'opened'
                Labels      = $Labels
                Milestone   = $Milestone
                Author      = ''
                WebUrl      = ''
                CreatedAt   = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
                UpdatedAt   = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
                Description = if ($Description) { $Description } else { '' }
            }

            if (-not $DryRun) {
                [System.IO.File]::WriteAllText($targetFile, (ConvertTo-WorkItemMarkdown -Item $newItem), [System.Text.UTF8Encoding]::new($false))
            }

            $localItems.Add($newItem)
            $rows.Add(@{ State = 'OK'; Label = 'WORK ITEM'; Detail = "Scaffolded work item template '$Title' -> .rivet/work-items/$fileName" })
            $artifacts.Add(".rivet/work-items/$fileName")

            # Update aggregated list dashboard
            $dashFile = Update-RivetWorkItemsListFile -Items $localItems
            $artifacts.Add(".rivet/workitems-list.md")
        }

        'View' {
            $targetItem = $null
            if ($Iid -gt 0) {
                $targetItem = $localItems | Where-Object { $_.Iid -eq $Iid } | Select-Object -First 1
            } elseif ($Title) {
                $targetItem = $localItems | Where-Object { $_.Title -match [regex]::Escape($Title) } | Select-Object -First 1
            } elseif ($localItems.Count -gt 0) {
                $targetItem = $localItems[0]
            }

            if (-not $targetItem) {
                $rows.Add(@{ State = 'FAIL'; Label = 'VIEW'; Detail = "Work item not found (Iid: $Iid, Title: '$Title')" })
            } else {
                $rows.Add(@{ State = 'OK'; Label = "ITEM #$($targetItem.Iid)"; Detail = "$($targetItem.Title) ($($targetItem.State))" })
                $rows.Add(@{ State = 'INFO'; Label = 'LABELS'; Detail = ($targetItem.Labels -join ', ') })
                $rows.Add(@{ State = 'INFO'; Label = 'AUTHOR'; Detail = $targetItem.Author })
                $rows.Add(@{ State = 'INFO'; Label = 'URL'; Detail = $targetItem.WebUrl })
                $rows.Add(@{ State = 'INFO'; Label = 'FILE'; Detail = $targetItem.File })

                if (-not $Raw) {
                    Write-Host ""
                    Write-Host "$cOrange┌─────────────────────────────────────────────────────────────┐$cReset"
                    Write-Host "$cOrange│$cReset $cBold$($targetItem.Title)$cReset"
                    Write-Host "$cOrange├─────────────────────────────────────────────────────────────┤$cReset"
                    Write-Host "$cDim  IID: #$($targetItem.Iid)  |  Status: $($targetItem.State)  |  Sync: $($targetItem.SyncAction)$cReset"
                    Write-Host "$cDim  Labels: $($targetItem.Labels -join ', ')$cReset"
                    Write-Host "$cOrange├─────────────────────────────────────────────────────────────┤$cReset"
                    Write-Host $targetItem.Description
                    Write-Host "$cOrange└─────────────────────────────────────────────────────────────┘$cReset"
                }
            }
        }

        { $_ -in @('Close', 'Reopen') } {
            $targetState = if ($Action -eq 'Close') { 'closed' } else { 'opened' }
            $targetItem = $null
            if ($Iid -gt 0) {
                $targetItem = $localItems | Where-Object { $_.Iid -eq $Iid } | Select-Object -First 1
            } elseif ($Title) {
                $targetItem = $localItems | Where-Object { $_.Title -match [regex]::Escape($Title) } | Select-Object -First 1
            }

            if (-not $targetItem) {
                $rows.Add(@{ State = 'FAIL'; Label = $Action.ToUpper(); Detail = "Work item not found (Iid: $Iid, Title: '$Title')" })
            } else {
                $targetItem.State = $targetState
                $targetItem.SyncAction = 'push'
                $targetItem.UpdatedAt = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
                if (-not $DryRun) {
                    [System.IO.File]::WriteAllText($targetItem.File, (ConvertTo-WorkItemMarkdown -Item $targetItem), [System.Text.UTF8Encoding]::new($false))
                }
                $rows.Add(@{ State = 'OK'; Label = $Action.ToUpper(); Detail = "Marked work item #$($targetItem.Iid) '$($targetItem.Title)' as $targetState (flagged for push)" })
                $artifacts.Add($targetItem.File)

                # Regenerate task dashboard
                $dashFile = Update-RivetWorkItemsListFile -Items $localItems
                $artifacts.Add(".rivet/workitems-list.md")
            }
        }

        'GenerateList' {
            $dashFile = Update-RivetWorkItemsListFile -Items $localItems
            $rows.Add(@{ State = 'OK'; Label = 'TASKLIST'; Detail = "Generated aggregated tasklist index -> $dashFile ($($localItems.Count) tasks)" })
            $artifacts.Add(".rivet/workitems-list.md")
        }

        'Pull' {
            if (-not $apiAvailable) {
                $rows.Add(@{ State = 'WARN'; Label = 'PULL'; Detail = 'GitLab API credentials not configured; using local work items without remote sync.' })
            } else {
                $baseUri = $Config.gitlab.baseUri.TrimEnd('/')
                $encodedProject = [System.Uri]::EscapeDataString($Config.project.path)
                $headers = @{ 'PRIVATE-TOKEN' = $token }

                # Determine if user requested a single IID or pulling items marked 'pull'
                $iidsToPull = [System.Collections.Generic.HashSet[int]]::new()
                if ($Iid -gt 0) {
                    [void]$iidsToPull.Add($Iid)
                } else {
                    foreach ($loc in $localItems) {
                        if ($null -ne $loc.Iid -and $loc.Iid -gt 0 -and $loc.SyncAction -ieq 'pull') {
                            [void]$iidsToPull.Add($loc.Iid)
                        }
                    }
                }

                if ($iidsToPull.Count -gt 0) {
                    # Targeted Pull for specific IID(s) only
                    foreach ($targetIid in $iidsToPull) {
                        try {
                            $cacheKey = "gitlab_issue_${encodedProject}_${targetIid}"
                            $issue = Invoke-RivetCachedOperation -Key $cacheKey -TtlSeconds 900 -ForceRefresh:$ForceRefresh -Tags @('gitlab_issues') -ScriptBlock {
                                $singleUri = "$baseUri/api/v4/projects/$encodedProject/issues/$targetIid"
                                Invoke-RestMethod -Uri $singleUri -Headers $headers -Method Get -TimeoutSec 15
                            }

                            if ($issue) {
                                # Fetch most recent comment if available
                                $recentComment = $null
                                try {
                                    $notesKey = "gitlab_issue_notes_${encodedProject}_${targetIid}"
                                    $notes = Invoke-RivetCachedOperation -Key $notesKey -TtlSeconds 600 -ForceRefresh:$ForceRefresh -Tags @('gitlab_issues') -ScriptBlock {
                                        Invoke-RestMethod -Uri "$baseUri/api/v4/projects/$encodedProject/issues/$targetIid/notes?sort=desc&per_page=5" -Headers $headers -Method Get -TimeoutSec 15
                                    }
                                    $userNote = @($notes | Where-Object { -not $_.system }) | Select-Object -First 1
                                    if ($userNote) {
                                        $recentComment = [pscustomobject]@{
                                            Author    = [string]$userNote.author.username
                                            CreatedAt = [string]$userNote.created_at
                                            Body      = [string]$userNote.body
                                        }
                                    }
                                } catch {}

                                $slug = ($issue.title.ToLower() -replace '[^a-z0-9]+', '-').Trim('-')
                                if ($slug.Length -gt 40) { $slug = $slug.Substring(0, 40) }
                                $fileName = "{0:D3}-$slug.md" -f [int]$issue.iid
                                $targetPath = [System.IO.Path]::Combine($workItemsDir, $fileName)

                                $itemObj = [pscustomobject]@{
                                    File          = $targetPath
                                    FileName      = $fileName
                                    Iid           = [int]$issue.iid
                                    Title         = [string]$issue.title
                                    SyncAction    = 'pull'
                                    State         = [string]$issue.state
                                    Labels        = @($issue.labels)
                                    Milestone     = if ($issue.milestone) { [string]$issue.milestone.title } else { '' }
                                    Author        = if ($issue.author) { [string]$issue.author.username } else { '' }
                                    WebUrl        = [string]$issue.web_url
                                    CreatedAt     = [string]$issue.created_at
                                    UpdatedAt     = [string]$issue.updated_at
                                    Description   = [string]$issue.description
                                    RecentComment = $recentComment
                                }

                                if (-not $DryRun) {
                                    [System.IO.File]::WriteAllText($targetPath, (ConvertTo-WorkItemMarkdown -Item $itemObj), [System.Text.UTF8Encoding]::new($false))
                                }
                                $artifacts.Add(".rivet/work-items/$fileName (#$($issue.iid))")
                                $rows.Add(@{ State = 'OK'; Label = "PULL #$($issue.iid)"; Detail = "Pulled issue #$($issue.iid) '$($issue.title)' ($($issue.state))" })
                            }
                        } catch {
                            $rows.Add(@{ State = 'FAIL'; Label = "PULL #$($targetIid)"; Detail = "Failed to pull issue #$($targetIid): $($_.Exception.Message)" })
                        }
                    }
                } else {
                    # General pull for all matching open issues
                    $cacheKey = "gitlab_issues_${encodedProject}_${State}"
                    $issues = Invoke-RivetCachedOperation -Key $cacheKey -TtlSeconds 900 -ForceRefresh:$ForceRefresh -Tags @('gitlab_issues') -ScriptBlock {
                        $stateParam = if ($State -eq 'all') { '' } else { "&state=$State" }
                        $uri = "$baseUri/api/v4/projects/$encodedProject/issues?per_page=100$stateParam"
                        Invoke-RestMethod -Uri $uri -Headers $headers -Method Get -TimeoutSec 15
                    }

                    $pulledCount = 0
                    foreach ($issue in $issues) {
                        $slug = ($issue.title.ToLower() -replace '[^a-z0-9]+', '-').Trim('-')
                        if ($slug.Length -gt 40) { $slug = $slug.Substring(0, 40) }
                        $fileName = "{0:D3}-$slug.md" -f [int]$issue.iid
                        $targetPath = [System.IO.Path]::Combine($workItemsDir, $fileName)

                        $itemObj = [pscustomobject]@{
                            File          = $targetPath
                            FileName      = $fileName
                            Iid           = [int]$issue.iid
                            Title         = [string]$issue.title
                            SyncAction    = 'pull'
                            State         = [string]$issue.state
                            Labels        = @($issue.labels)
                            Milestone     = if ($issue.milestone) { [string]$issue.milestone.title } else { '' }
                            Author        = if ($issue.author) { [string]$issue.author.username } else { '' }
                            WebUrl        = [string]$issue.web_url
                            CreatedAt     = [string]$issue.created_at
                            UpdatedAt     = [string]$issue.updated_at
                            Description   = [string]$issue.description
                            RecentComment = $null
                        }

                        if (-not $DryRun) {
                            [System.IO.File]::WriteAllText($targetPath, (ConvertTo-WorkItemMarkdown -Item $itemObj), [System.Text.UTF8Encoding]::new($false))
                        }
                        $artifacts.Add(".rivet/work-items/$fileName (#$($issue.iid))")
                        $pulledCount++
                    }
                    $rows.Add(@{ State = 'OK'; Label = 'PULL'; Detail = "Successfully pulled $pulledCount issue(s) from GitLab into .rivet/work-items/" })
                }

                # Update aggregated list dashboard
                $dashFile = Update-RivetWorkItemsListFile -Items $localItems
                $artifacts.Add(".rivet/workitems-list.md")
            }
        }

        { $_ -in @('Push', 'Sync') } {
            if (-not $apiAvailable) {
                $rows.Add(@{ State = 'WARN'; Label = 'PUSH'; Detail = 'GitLab API credentials not configured (GITLAB_TOKEN missing); push skipped.' })
            } else {
                $baseUri = $Config.gitlab.baseUri.TrimEnd('/')
                $encodedProject = [System.Uri]::EscapeDataString($Config.project.path)
                $headers = @{ 'PRIVATE-TOKEN' = $token }
                $pushedCount = 0

                # Filter items to push: explicit Iid, or items where SyncAction == 'push'
                $itemsToPush = @($localItems | Where-Object {
                    ($Iid -gt 0 -and $_.Iid -eq $Iid) -or ($_.SyncAction -ieq 'push') -or ($Action -eq 'Push' -and $localItems.Count -eq 1)
                })

                if ($itemsToPush.Count -eq 0) {
                    $rows.Add(@{ State = 'INFO'; Label = 'PUSH'; Detail = 'No work items flagged with `Sync Action: push`. To push changes, update the metadata table in the work item file.' })
                } else {
                    foreach ($item in $itemsToPush) {
                        try {
                            if ($null -ne $item.Iid -and $item.Iid -gt 0) {
                                # Update existing remote issue
                                $uri = "$baseUri/api/v4/projects/$encodedProject/issues/$($item.Iid)"
                                $body = @{
                                    title       = $item.Title
                                    description = $item.Description
                                    labels      = ($item.Labels -join ',')
                                    state_event = if ($item.State -ieq 'closed') { 'close' } else { 'reopen' }
                                }
                                if (-not $DryRun) {
                                    $null = Invoke-RestMethod -Uri $uri -Headers $headers -Method Put -Body ($body | ConvertTo-Json) -ContentType 'application/json' -TimeoutSec 15
                                    # Reset Sync Action back to pull
                                    $item.SyncAction = 'pull'
                                    $item.UpdatedAt = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
                                    [System.IO.File]::WriteAllText($item.File, (ConvertTo-WorkItemMarkdown -Item $item), [System.Text.UTF8Encoding]::new($false))
                                    # Invalidate cache for this issue
                                    Remove-RivetCache -Key "gitlab_issue_${encodedProject}_$($item.Iid)"
                                }
                                $rows.Add(@{ State = 'OK'; Label = "ISSUE #$($item.Iid)"; Detail = "Updated GitLab issue #$($item.Iid) '$($item.Title)'" })
                            } else {
                                # Create new remote issue
                                $uri = "$baseUri/api/v4/projects/$encodedProject/issues"
                                $body = @{
                                    title       = $item.Title
                                    description = $item.Description
                                    labels      = ($item.Labels -join ',')
                                }
                                if (-not $DryRun) {
                                    $created = Invoke-RestMethod -Uri $uri -Headers $headers -Method Post -Body ($body | ConvertTo-Json) -ContentType 'application/json' -TimeoutSec 15
                                    $item.Iid = [int]$created.iid
                                    $item.WebUrl = [string]$created.web_url
                                    $item.SyncAction = 'pull'
                                    $item.CreatedAt = [string]$created.created_at
                                    $item.UpdatedAt = [string]$created.updated_at
                                    
                                    # Rename draft file to standard {iid}-{slug}.md
                                    $slug = ($item.Title.ToLower() -replace '[^a-z0-9]+', '-').Trim('-')
                                    $newFileName = "{0:D3}-$slug.md" -f $item.Iid
                                    $newPath = [System.IO.Path]::Combine($workItemsDir, $newFileName)
                                    [System.IO.File]::WriteAllText($newPath, (ConvertTo-WorkItemMarkdown -Item $item), [System.Text.UTF8Encoding]::new($false))
                                    if ($item.File -ne $newPath -and [System.IO.File]::Exists($item.File)) {
                                        [System.IO.File]::Delete($item.File)
                                    }
                                    # Invalidate cache
                                    Remove-RivetCache -Tag 'gitlab_issues'
                                }
                                $rows.Add(@{ State = 'OK'; Label = 'NEW ISSUE'; Detail = "Created remote GitLab issue for '$($item.Title)'" })
                            }
                            $pushedCount++
                        } catch {
                            $rows.Add(@{ State = 'FAIL'; Label = 'PUSH'; Detail = "Failed to push work item '$($item.Title)': $($_.Exception.Message)" })
                        }
                    }
                    $rows.Add(@{ State = 'OK'; Label = 'PUSH SYNC'; Detail = "Processed $pushedCount local work item(s) to GitLab" })
                }

                # Update aggregated list dashboard
                $dashFile = Update-RivetWorkItemsListFile -Items $localItems
                $artifacts.Add(".rivet/workitems-list.md")
            }
        }

        default { # List
            $count = $localItems.Count
            $rows.Add(@{ State = 'OK'; Label = 'WORK ITEMS'; Detail = "Discovered $count local work item(s) under .rivet/work-items/" })
            foreach ($item in $localItems) {
                $stateBadge = if ($item.State -ieq 'opened') { '[OPEN]' } else { '[CLOSED]' }
                $iidStr = if ($item.Iid) { "#$($item.Iid)" } else { '[DRAFT]' }
                $syncTag = if ($item.SyncAction -ieq 'push') { " $cOrange[PUSH]$cReset" } else { " $cDim[PULL]$cReset" }
                $lblStr = if ($item.Labels -and @($item.Labels).Count -gt 0) { " ($($item.Labels -join ', '))" } else { '' }
                $rows.Add(@{
                    State  = if ($item.State -ieq 'opened') { 'OK' } else { 'INFO' }
                    Label  = $iidStr
                    Detail = "$stateBadge $($item.Title)$syncTag$lblStr"
                })
            }
        }
    }

    # Record Cache Telemetry if cache metrics are available
    if (Get-Command -Name 'Get-RivetCacheMetrics' -CommandType Function -ErrorAction SilentlyContinue) {
        $metrics = Get-RivetCacheMetrics
        if ($metrics.TotalRequests -gt 0) {
            $artifacts.Add("Cache Telemetry: $($metrics.Hits) hits / $($metrics.TotalRequests) reqs ($($metrics.HitRatePercentage)%) | $($metrics.TotalSizeBytes) bytes")
        }
    }

    $sw.Stop()
    $runMode = if ($DryRun) { 'DRY RUN' } else { 'APPLY' }
    $projDisplayName = if ($Config) { $Config.project.displayName } else { '' }

    $report = Write-RivetReportCard `
        -Title "RIVET WORK ITEMS - $Action" `
        -Mode $runMode `
        -Elapsed $sw.Elapsed `
        -ProjectName $projDisplayName `
        -Rows $rows.ToArray() `
        -Artifacts $artifacts.ToArray() `
        -Raw:$Raw

    return $report
}
