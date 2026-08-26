<#
.SYNOPSIS
    Displays a resize-aware, keyboard-driven terminal menu.
.DESCRIPTION
    Redraws atomically when the terminal size or selection changes. Wide
    terminals render label and description columns. Narrow terminals stack
    and wrap selected detail. Short terminals expose a scrolling viewport.
#>
function Get-SMenuTerminalSize {
    [CmdletBinding()]
    param()

    $width = try { [Console]::WindowWidth } catch { 120 }
    $height = try { [Console]::WindowHeight } catch { 30 }
    [pscustomobject]@{
        Width = [Math]::Max(24, $width)
        Height = [Math]::Max(10, $height)
    }
}

function Split-SMenuText {
    [CmdletBinding()]
    param(
        [AllowEmptyString()][string]$Text,
        [ValidateRange(1, [int]::MaxValue)][int]$Width
    )

    $lines = [System.Collections.Generic.List[string]]::new()
    foreach ($paragraph in ($Text -split '\r?\n')) {
        $remaining = $paragraph.Trim()
        if (-not $remaining.Length) { $lines.Add(''); continue }
        while ($remaining.Length -gt $Width) {
            $breakAt = $remaining.LastIndexOf(' ', $Width)
            if ($breakAt -lt 1) { $breakAt = $Width }
            $lines.Add($remaining.Substring(0, $breakAt).TrimEnd())
            $remaining = $remaining.Substring($breakAt).TrimStart()
        }
        $lines.Add($remaining)
    }
    return $lines.ToArray()
}

function Get-SMenuLayout {
    [CmdletBinding()]
    param(
        [ValidateRange(1, [int]::MaxValue)][int]$TerminalWidth,
        [ValidateRange(1, [int]::MaxValue)][int]$TerminalHeight,
        [ValidateRange(1, [int]::MaxValue)][int]$ItemCount,
        [ValidateRange(3, 100)][int]$ViewSize = 30
    )

    $frameWidth = [Math]::Max(22, [Math]::Min(132, $TerminalWidth - 2))
    $contentWidth = [Math]::Max(16, $frameWidth - 4)
    $wide = $contentWidth -ge 76
    $reservedRows = if ($wide) { 8 } else { 11 }
    $visibleItems = [Math]::Max(1, [Math]::Min([Math]::Min($ViewSize, $ItemCount), $TerminalHeight - $reservedRows))
    $labelWidth = if ($wide) { [Math]::Max(20, [int][Math]::Floor($contentWidth * 0.38)) } else { $contentWidth - 4 }
    [pscustomobject]@{
        FrameWidth = $frameWidth
        ContentWidth = $contentWidth
        Wide = $wide
        VisibleItems = $visibleItems
        LabelWidth = $labelWidth
        DescriptionWidth = if ($wide) { [Math]::Max(20, $contentWidth - $labelWidth - 5) } else { $contentWidth - 4 }
    }
}

function Show-SMenu {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][object[]]$Items,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Title,
        [ValidateRange(0, [int]::MaxValue)][int]$DefaultIndex = 0,
        [ValidateRange(3, 100)][int]$ViewSize = 30
    )

    if ([Console]::IsInputRedirected -or [Console]::IsOutputRedirected) {
        throw 'Show-SMenu requires an interactive terminal.'
    }
    if ($DefaultIndex -ge $Items.Count) { $DefaultIndex = 0 }

    $esc = [char]27
    $colors = [ordered]@{
        Reset = "$esc[0m"
        Border = "$esc[38;2;48;58;78m"
        Accent = "$esc[1;38;2;0;210;255m"
        Secondary = "$esc[38;2;255;70;180m"
        Text = "$esc[38;2;224;230;240m"
        Muted = "$esc[38;2;130;142;166m"
        Faint = "$esc[38;2;82;94;118m"
        Selected = "$esc[1;38;2;255;255;255m"
        Multi = "$esc[1;38;2;196;112;255m"
    }
    $currentIndex = $DefaultIndex
    $topIndex = 0
    $lastWidth = -1
    $lastHeight = -1
    $needsRedraw = $true

    function Get-ItemTitle([object]$Item) {
        $label = [string]$Item.Label
        $multiProperty = $Item.PSObject.Properties['MultiAction']
        if ($null -ne $multiProperty -and [bool]$multiProperty.Value) { return "$label [MA]" }
        return $label
    }

    function Write-Frame([object]$Size) {
        $layout = Get-SMenuLayout -TerminalWidth $Size.Width -TerminalHeight $Size.Height -ItemCount $Items.Count -ViewSize $ViewSize
        if ($currentIndex -lt $topIndex) { $topIndex = $currentIndex }
        if ($currentIndex -ge ($topIndex + $layout.VisibleItems)) { $topIndex = $currentIndex - $layout.VisibleItems + 1 }
        $topIndex = [Math]::Max(0, [Math]::Min($topIndex, [Math]::Max(0, $Items.Count - $layout.VisibleItems)))

        $inner = $layout.FrameWidth - 2
        $builder = [System.Text.StringBuilder]::new([Math]::Max(2048, $layout.FrameWidth * $Size.Height))
        $rule = [string]::new([char]0x2500, $inner)
        [void]$builder.Append("$esc[H$esc[2J")
        [void]$builder.AppendLine("$($colors.Border)┌$rule┐$($colors.Reset)")
        $titleRow = Pad-AnsiString -Text "$($colors.Accent) $Title $($colors.Reset)" -Width $inner -Align Left -Truncate
        [void]$builder.AppendLine("$($colors.Border)│$($colors.Reset)$titleRow$($colors.Border)│$($colors.Reset)")
        $position = "$($currentIndex + 1)/$($Items.Count)"
        $hintBudget = [Math]::Max(1, $inner - $position.Length - 1)
        $hint = Pad-AnsiString -Text "$($colors.Muted) arrows navigate  enter select  home/end jump  esc back$($colors.Reset)" -Width $hintBudget -Align Left -Truncate
        [void]$builder.AppendLine("$($colors.Border)│$($colors.Reset)$hint $($colors.Faint)$position$($colors.Reset)$($colors.Border)│$($colors.Reset)")
        [void]$builder.AppendLine("$($colors.Border)├$rule┤$($colors.Reset)")

        for ($row = 0; $row -lt $layout.VisibleItems; $row++) {
            $itemIndex = $topIndex + $row
            if ($itemIndex -ge $Items.Count) {
                [void]$builder.AppendLine("$($colors.Border)│$($colors.Reset)$(' ' * $inner)$($colors.Border)│$($colors.Reset)")
                continue
            }
            $item = $Items[$itemIndex]
            $selected = $itemIndex -eq $currentIndex
            $titlePlain = Get-ItemTitle $item
            $multi = $titlePlain.EndsWith(' [MA]', [System.StringComparison]::Ordinal)
            $baseTitle = if ($multi) { $titlePlain.Substring(0, $titlePlain.Length - 5) } else { $titlePlain }
            $marker = if ($selected) { ' > ' } else { '   ' }
            $titleColor = if ($selected) { $colors.Selected } else { $colors.Text }
            $titleText = "$titleColor$baseTitle$($colors.Reset)"
            if ($multi) { $titleText += "$($colors.Multi) [MA]$($colors.Reset)" }
            $descriptionProperty = $item.PSObject.Properties['Description']
            $description = if ($null -eq $descriptionProperty) { '' } else { [string]$descriptionProperty.Value }

            if ($layout.Wide) {
                $labelCell = Pad-AnsiString -Text "$marker$titleText" -Width ($layout.LabelWidth + 3) -Align Left -Truncate
                $descriptionCell = Pad-AnsiString -Text "$($colors.Muted)$description$($colors.Reset)" -Width $layout.DescriptionWidth -Align Left -Truncate
                $line = Pad-AnsiString -Text "$labelCell  $descriptionCell" -Width $inner -Align Left -Truncate
            } else {
                $line = Pad-AnsiString -Text "$marker$titleText" -Width $inner -Align Left -Truncate
            }
            [void]$builder.AppendLine("$($colors.Border)│$($colors.Reset)$line$($colors.Border)│$($colors.Reset)")
        }

        [void]$builder.AppendLine("$($colors.Border)├$rule┤$($colors.Reset)")
        $selectedItem = $Items[$currentIndex]
        $detailTitle = "DETAIL  $(Get-ItemTitle $selectedItem)"
        $detailLine = Pad-AnsiString -Text "$($colors.Secondary)$detailTitle$($colors.Reset)" -Width $inner -Align Left -Truncate
        [void]$builder.AppendLine("$($colors.Border)│$($colors.Reset)$detailLine$($colors.Border)│$($colors.Reset)")
        $detailLines = @(Split-SMenuText -Text ([string]$selectedItem.Description) -Width ([Math]::Max(8, $inner - 4)))
        $detailRows = if ($layout.Wide) { 1 } else { [Math]::Min(3, [Math]::Max(1, $detailLines.Count)) }
        for ($index = 0; $index -lt $detailRows; $index++) {
            $detailText = if ($index -lt $detailLines.Count) { $detailLines[$index] } else { '' }
            $detail = Pad-AnsiString -Text "$($colors.Muted)  $detailText$($colors.Reset)" -Width $inner -Align Left -Truncate
            [void]$builder.AppendLine("$($colors.Border)│$($colors.Reset)$detail$($colors.Border)│$($colors.Reset)")
        }
        [void]$builder.Append("$($colors.Border)└$rule┘$($colors.Reset)$esc[J")
        [Console]::Write($builder.ToString())
    }

    try {
        Hide-TerminalCursor
        while ($true) {
            $size = Get-SMenuTerminalSize
            if ($size.Width -ne $lastWidth -or $size.Height -ne $lastHeight) {
                $lastWidth = $size.Width
                $lastHeight = $size.Height
                $needsRedraw = $true
            }
            if ($needsRedraw) { Write-Frame $size; $needsRedraw = $false }
            if (-not [Console]::KeyAvailable) {
                [System.Threading.Thread]::Sleep(40)
                continue
            }
            $key = [Console]::ReadKey($true)
            switch ($key.Key) {
                'UpArrow' { if ($currentIndex -gt 0) { $currentIndex--; $needsRedraw = $true } }
                'DownArrow' { if ($currentIndex -lt ($Items.Count - 1)) { $currentIndex++; $needsRedraw = $true } }
                'PageUp' { $currentIndex = [Math]::Max(0, $currentIndex - 5); $needsRedraw = $true }
                'PageDown' { $currentIndex = [Math]::Min($Items.Count - 1, $currentIndex + 5); $needsRedraw = $true }
                'Home' { $currentIndex = 0; $needsRedraw = $true }
                'End' { $currentIndex = $Items.Count - 1; $needsRedraw = $true }
                'Enter' { return $Items[$currentIndex].Value }
                'Escape' { return $null }
            }
        }
    } finally {
        Show-TerminalCursor
        [Console]::ResetColor()
    }
}
