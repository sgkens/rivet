function Write-RivetReportCard {
    <#
    .SYNOPSIS
        Renders an elegant, non-tear ASCII TUI completion report card.
    .DESCRIPTION
        Outputs a structured report card with TrueColor gradient borders (orange to off-black),
        project context, execution mode, duration, operation breakdown with status badges,
        and generated artifacts. Long text strings are wrapped into formatted paragraph blocks.
        Supports -Raw to suppress console output and return structured data for compound workflows.
    .PARAMETER Title
        Header title of the report card.
    .PARAMETER Mode
        Execution mode string ('APPLY' or 'DRY RUN').
    .PARAMETER Elapsed
        Execution duration as a TimeSpan.
    .PARAMETER ProjectName
        Display name or identity of the repository/project.
    .PARAMETER Version
        Current or resolved SemVer version string.
    .PARAMETER Branch
        Active Git branch name.
    .PARAMETER Head
        Short commit SHA of HEAD.
    .PARAMETER Upstream
        Upstream remote branch tracking status.
    .PARAMETER Rows
        Array of row hashtables containing @{ State = 'OK'|'SKIP'|'FAIL'|'WARN'|'ACT'|'INFO'; Label = '...'; Detail = '...' }.
    .PARAMETER Artifacts
        Array of file paths, commit messages, tags, or URLs modified/created.
    .PARAMETER Width
        Explicit width override. Defaults to responsive console width detection.
    .PARAMETER Raw
        Suppresses console printing and returns the structured report object.
    .PARAMETER PassThru
        Returns the rendered string lines in addition to console printing.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)][string]$Title,
        [Parameter()][string]$Mode = 'APPLY',
        [Parameter()][timespan]$Elapsed = [timespan]::Zero,
        [Parameter()][string]$ProjectName = '',
        [Parameter()][string]$Version = '',
        [Parameter()][string]$Branch = '',
        [Parameter()][string]$Head = '',
        [Parameter()][string]$Upstream = '',
        [Parameter()][hashtable[]]$Rows = @(),
        [Parameter()][string[]]$Artifacts = @(),
        [Parameter()][int]$Width = 0,
        [switch]$Raw,
        [switch]$PassThru
    )

    $reportData = [pscustomobject]@{
        Title       = $Title
        Mode        = $Mode
        Elapsed     = $Elapsed
        ProjectName = $ProjectName
        Version     = $Version
        Branch      = $Branch
        Head        = $Head
        Upstream    = $Upstream
        Rows        = $Rows
        Artifacts   = $Artifacts
        Success     = (-not ($Rows | Where-Object { $_.State -in @('FAIL', 'ERROR') }))
    }

    if ($Raw) {
        return $reportData
    }

    # Discover responsive terminal width
    $termWidth = if ($Width -gt 0) { $Width } else {
        try { [Console]::WindowWidth } catch { 100 }
    }
    $panelWidth = [Math]::Max(40, [Math]::Min(120, $termWidth - 2))
    $contentWidth = $panelWidth - 4 # Accounting for '│ ' and ' │'

    # Color definitions
    $cDim     = "`e[38;2;120;130;145m"
    $cBold    = "`e[1m"
    $cReset   = "`e[0m"
    $cOrange  = "`e[38;2;255;130;0m"
    $cGreen   = "`e[38;2;80;220;150m"
    $cRed     = "`e[38;2;255;90;105m"
    $cYellow  = "`e[38;2;255;195;75m"
    $cCyan    = "`e[38;2;0;200;255m"
    $cWhite   = "`e[38;2;230;235;245m"

    $statusBadges = @{
        'OK'       = "$cGreen[SUC]$cReset"
        'SUC'      = "$cGreen[SUC]$cReset"
        'SUCCESS'  = "$cGreen[SUC]$cReset"
        'ACT'      = "$cOrange[ACT]$cReset"
        'ACTION'   = "$cOrange[ACT]$cReset"
        'RUN'      = "$cOrange[ACT]$cReset"
        'SKIP'     = "$cYellow[SKIP]$cReset"
        'DISABLED' = "$cYellow[SKIP]$cReset"
        'FAIL'     = "$cRed[FAIL]$cReset"
        'ERROR'    = "$cRed[FAIL]$cReset"
        'WRN'      = "$cYellow[WRN]$cReset"
        'WARN'     = "$cYellow[WRN]$cReset"
        'WARNING'  = "$cYellow[WRN]$cReset"
        'INFO'     = "$cCyan[INF]$cReset"
        'INF'      = "$cCyan[INF]$cReset"
    }

    $panelLines = [System.Collections.Generic.List[string]]::new()

    # 1. Header Metadata Section
    if ($ProjectName -or $Version) {
        $versionTag = if ($Version) { " $cDim(v$Version)$cReset" } else { '' }
        $projStr = "$cWhite$ProjectName$cReset$versionTag"
        $panelLines.Add("  ${cDim}PROJECT${cReset}   $projStr")
    }
    if ($Branch -or $Head) {
        $headTag = if ($Head) { " $cDim@ $Head$cReset" } else { '' }
        $upstreamTag = if ($Upstream) { " $cDim| $Upstream$cReset" } else { '' }
        $gitStr = "$cWhite$Branch$cReset$headTag$upstreamTag"
        $panelLines.Add("  ${cDim}CONTEXT${cReset}   $gitStr")
    }
    $modeColor = if ($Mode -ieq 'APPLY') { $cGreen } else { $cYellow }
    $elapsedStr = if ($Elapsed.TotalMilliseconds -gt 0) {
        if ($Elapsed.TotalSeconds -ge 1) { "{0:N2}s" -f $Elapsed.TotalSeconds } else { "{0}ms" -f [int]$Elapsed.TotalMilliseconds }
    } else { '' }
    $elapsedTag = if ($elapsedStr) { " $cDim| $elapsedStr$cReset" } else { '' }
    $modeLine = "  ${cDim}MODE${cReset}      $modeColor$Mode$cReset$elapsedTag"
    $panelLines.Add($modeLine)

    # 2. Execution Rows Breakdown
    if ($Rows -and @($Rows).Count -gt 0) {
        $panelLines.Add('')
        $panelLines.Add("  ${cOrange}${cBold}EXECUTION BREAKDOWN${cReset}")

        foreach ($row in $Rows) {
            $st = if ($row.State) { [string]$row.State } else { 'OK' }
            $badge = if ($statusBadges.ContainsKey($st)) { $statusBadges[$st] } else { "[${st}]" }
            $label = if ($row.Label) { "$cWhite$($row.Label)$cReset" } else { '' }
            $prefix = "    $badge $($label.PadRight(16))"
            $detail = if ($row.Detail) { [string]$row.Detail } else { '' }

            $availableDetailWidth = [Math]::Max(20, $contentWidth - 24)
            $detailLines = Split-SMenuText -Text $detail -Width $availableDetailWidth

            if (@($detailLines).Count -gt 0) {
                $panelLines.Add("$prefix $($detailLines[0])")
                for ($i = 1; $i -lt @($detailLines).Count; $i++) {
                    $panelLines.Add("                   $cDim$($detailLines[$i])$cReset")
                }
            } else {
                $panelLines.Add($prefix)
            }
        }
    }

    # 3. Artifacts & Outputs
    if ($Artifacts -and @($Artifacts).Count -gt 0) {
        $panelLines.Add('')
        $panelLines.Add("  ${cOrange}${cBold}ARTIFACTS & OUTPUTS${cReset}")
        foreach ($art in $Artifacts) {
            $artLines = Split-SMenuText -Text $art -Width ($contentWidth - 6)
            if (@($artLines).Count -gt 0) {
                $panelLines.Add("    $cDim■$cReset $cWhite$($artLines[0])$cReset")
                for ($i = 1; $i -lt @($artLines).Count; $i++) {
                    $panelLines.Add("      $cDim$($artLines[$i])$cReset")
                }
            }
        }
    }

    # 4. Summary Status Line
    $panelLines.Add('')
    $sucCount = @($Rows | Where-Object { $_.State -in @('OK', 'SUC', 'SUCCESS') }).Count
    $skipCount = @($Rows | Where-Object { $_.State -in @('SKIP', 'DISABLED') }).Count
    $failCount = @($Rows | Where-Object { $_.State -in @('FAIL', 'ERROR') }).Count

    $summaryBadge = if ($failCount -eq 0) {
        "$cGreen${cBold}RESULT: SUCCESS$cReset $cDim($sucCount completed, $skipCount skipped, 0 failed)$cReset"
    } else {
        "$cRed${cBold}RESULT: FAILED$cReset $cDim($failCount failed, $sucCount completed, $skipCount skipped)$cReset"
    }
    $panelLines.Add("  $summaryBadge")

    # Render Panel using New-TuiPanel with Title and Gradient Borders
    $output = New-TuiPanel -Content $panelLines.ToArray() -Title $Title -Width $panelWidth
    $outputLines = @($output -split '\r?\n')

    if ($PassThru) {
        return $outputLines
    }

    foreach ($line in $outputLines) {
        [Console]::WriteLine($line)
    }

    return $reportData
}
