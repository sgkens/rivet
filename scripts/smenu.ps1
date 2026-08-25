<#
.SYNOPSIS
    Displays an ordered, keyboard-driven terminal selection menu.
.DESCRIPTION
    Renders only the menu region, returns the selected item value, and restores
    the cursor when the operation is cancelled. Arrow keys, Home, End, Enter,
    and Escape are supported. No global console colors or screen clears are used.
.PARAMETER Items
    Ordered menu items. Each item must expose Label and Value properties.
.PARAMETER Title
    Heading displayed above the menu.
.PARAMETER DefaultIndex
    Zero-based item selected when the menu opens.
.PARAMETER ViewSize
    Maximum number of visible items.
.EXAMPLE
    $selected = Show-SMenu -Title 'Commit type' -Items @(
        [pscustomobject]@{ Label = 'feat - feature'; Value = 'feat' }
        [pscustomobject]@{ Label = 'fix  - bug fix'; Value = 'fix' }
    )
#>
function Show-SMenu {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [object[]]$Items,
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Title,
        [ValidateRange(0, [int]::MaxValue)]
        [int]$DefaultIndex = 0,
        [ValidateRange(3, 30)]
        [int]$ViewSize = 10
    )

    if ([Console]::IsInputRedirected -or [Console]::IsOutputRedirected) {
        throw 'Show-SMenu requires an interactive terminal.'
    }
    if ($DefaultIndex -ge $Items.Count) { $DefaultIndex = 0 }

    $esc = [char]27
    $palette = @{
        Accent = @(0, 200, 255); GradientEnd = @(255, 60, 180)
        Muted = @(145, 155, 175); Text = @(220, 225, 235); Description = @(92, 102, 122)
    }
    $visibleCount = [Math]::Min($ViewSize, $Items.Count)
    $currentIndex = $DefaultIndex
    $topIndex = [Math]::Max(0, [Math]::Min($currentIndex, $Items.Count - $visibleCount))

    function Write-SMenuLine {
        param([string]$Text, [int[]]$Color, [switch]$Bold)
        $weight = if ($Bold) { '1;' } else { '' }
        [Console]::Write("$esc[2K`r$esc[${weight}38;2;$($Color[0]);$($Color[1]);$($Color[2])m$Text$esc[0m")
    }

    function Format-SMenuText {
        param([AllowEmptyString()][string]$Text, [int[]]$Color, [switch]$Bold, [switch]$Italic)
        $styles = [System.Collections.Generic.List[string]]::new(2)
        if ($Bold) { $styles.Add('1') }
        if ($Italic) { $styles.Add('3') }
        $stylePrefix = if ($styles.Count) { ($styles -join ';') + ';' } else { '' }
        return "$esc[${stylePrefix}38;2;$($Color[0]);$($Color[1]);$($Color[2])m$Text$esc[0m"
    }

    function Format-SMenuGradient {
        param([AllowEmptyString()][string]$Text)
        if ($Text.Length -eq 0) { return '' }
        $builder = [System.Text.StringBuilder]::new($Text.Length * 24)
        $denominator = [Math]::Max(1, $Text.Length - 1)
        for ($index = 0; $index -lt $Text.Length; $index++) {
            $ratio = $index / $denominator
            $red = [int]($palette.Accent[0] + (($palette.GradientEnd[0] - $palette.Accent[0]) * $ratio))
            $green = [int]($palette.Accent[1] + (($palette.GradientEnd[1] - $palette.Accent[1]) * $ratio))
            $blue = [int]($palette.Accent[2] + (($palette.GradientEnd[2] - $palette.Accent[2]) * $ratio))
            [void]$builder.Append("$esc[1;3;38;2;$red;$green;${blue}m$($Text[$index])")
        }
        [void]$builder.Append("$esc[0m")
        return $builder.ToString()
    }

    function Limit-SMenuText {
        param([AllowEmptyString()][string]$Text, [int]$MaximumLength)
        if ($MaximumLength -le 0) { return '' }
        if ($Text.Length -le $MaximumLength) { return $Text }
        if ($MaximumLength -le 3) { return $Text.Substring(0, $MaximumLength) }
        return $Text.Substring(0, $MaximumLength - 3) + '...'
    }

    function Render-SMenu {
        param([switch]$Redraw)

        $terminalWidth = try { [Console]::WindowWidth } catch { 120 }
        if ($terminalWidth -lt 20) { $terminalWidth = 20 }
        # Leave the final terminal column unused. Writing into it can trigger an
        # automatic wrap that moves the saved redraw origin and duplicates rows.
        $maximumRowWidth = $terminalWidth - 1
        if ($Redraw) {
            # Rewind only the rows owned by this menu. Relative movement remains
            # stable when the terminal scrolls; saved cursor slots do not.
            [Console]::Write("$esc[$($visibleCount + 2)A`r")
        }
        Write-SMenuLine -Text (Limit-SMenuText -Text $Title -MaximumLength $maximumRowWidth) -Color $palette.Accent -Bold
        [Console]::WriteLine()
        Write-SMenuLine -Text (Limit-SMenuText -Text '  up/down navigate  enter select  esc cancel' -MaximumLength $maximumRowWidth) -Color $palette.Muted
        [Console]::WriteLine()
        $labelWidth = 0
        foreach ($menuItem in $Items) { $labelWidth = [Math]::Max($labelWidth, ([string]$menuItem.Label).Length) }
        $contentWidth = [Math]::Max(8, $maximumRowWidth - 5)
        $labelBudget = [Math]::Min($labelWidth, [Math]::Max(8, [int][Math]::Floor($contentWidth * 0.42)))
        for ($row = 0; $row -lt $visibleCount; $row++) {
            $itemIndex = $topIndex + $row
            $selected = $itemIndex -eq $currentIndex
            $label = [string]$Items[$itemIndex].Label
            $descriptionProperty = $Items[$itemIndex].PSObject.Properties['Description']
            $description = if ($null -eq $descriptionProperty) { '' } else { [string]$descriptionProperty.Value }
            $descriptionBudget = $contentWidth - $labelBudget - 2
            $showDescription = $description -and $descriptionBudget -ge 8
            if ($showDescription) {
                $renderedLabel = (Limit-SMenuText -Text $label -MaximumLength $labelBudget).PadRight($labelBudget)
                $renderedDescription = Limit-SMenuText -Text $description -MaximumLength $descriptionBudget
            } else {
                $renderedLabel = Limit-SMenuText -Text $label -MaximumLength $contentWidth
                $renderedDescription = ''
            }
            [Console]::Write("$esc[2K`r")
            if ($selected) {
                # The active row intentionally receives one additional leading
                # space. Padding is calculated before ANSI gradient encoding.
                [Console]::Write('   ')
                [Console]::Write((Format-SMenuGradient -Text "> $renderedLabel"))
            } else {
                [Console]::Write('    ')
                [Console]::Write((Format-SMenuText -Text $renderedLabel -Color $palette.Text))
            }
            if ($showDescription) {
                [Console]::Write((Format-SMenuText -Text "  $renderedDescription" -Color $palette.Description))
            }
            [Console]::WriteLine()
        }
    }

    try {
        [Console]::Write("$esc[?25l")
        Render-SMenu
        while ($true) {
            $key = [Console]::ReadKey($true)
            switch ($key.Key) {
                'UpArrow' { if ($currentIndex -gt 0) { $currentIndex-- } }
                'DownArrow' { if ($currentIndex -lt ($Items.Count - 1)) { $currentIndex++ } }
                'Home' { $currentIndex = 0 }
                'End' { $currentIndex = $Items.Count - 1 }
                'Enter' { return $Items[$currentIndex].Value }
                'Escape' { return $null }
            }
            if ($currentIndex -lt $topIndex) { $topIndex = $currentIndex }
            if ($currentIndex -ge ($topIndex + $visibleCount)) { $topIndex = $currentIndex - $visibleCount + 1 }
            Render-SMenu -Redraw
        }
    } finally {
        [Console]::Write("$esc[?25h")
        [Console]::ResetColor()
    }
}
