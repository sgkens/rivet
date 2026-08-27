# ------------------------------------------------------------------------------
# FUNCTION: New-TuiPanel
# ------------------------------------------------------------------------------
function New-TuiPanel {
    <#
    .SYNOPSIS
        Renders a bordered TUI panel with an orange-to-offblack gradient border.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true, ValueFromPipeline=$true)]
        [AllowEmptyString()]
        [string[]]$Content,

        [Parameter(Mandatory=$false)]
        [string]$Title = "",

        [Parameter(Mandatory=$false)]
        [int]$Width = 0,

        [Parameter(Mandatory=$false)]
        [ValidateSet('Thin', 'Double', 'Rounded')]
        [string]$BorderStyle = 'Rounded',

        [Parameter(Mandatory=$false)]
        [hashtable]$ColorPalette = @{ Border = @(255, 130, 0); Title = @(0, 210, 255) },

        [Parameter(Mandatory=$false)]
        [ValidateSet('Left', 'Center', 'Right')]
        [string]$Alignment = 'Left',

        [Parameter(Mandatory=$false)]
        [int]$Padding = 1
    )

    begin {
        $internalContent = [System.Collections.Generic.List[string]]::new()
    }

    process {
        foreach ($line in $Content) {
            foreach ($splitLine in ($line -split '\r?\n')) {
                $internalContent.Add($splitLine)
            }
        }
    }

    end {
        $ui = Get-TerminalUI -BorderStyle $BorderStyle
        $palette = Get-TerminalPalette -ColorPalette $ColorPalette
        $titleCode = (& $palette.GetStaticColor 'Title')
        if ([string]::IsNullOrWhiteSpace($titleCode)) { $titleCode = "1;38;2;0;210;255" }

        $orange = @(255, 130, 0)
        $offBlack = @(40, 44, 54)

        $ansiRegex = [char]27 + '\[[0-9;]*[a-zA-Z]'
        $contentMaxWidth = 0

        foreach ($line in $internalContent) {
            $len = ($line -replace $ansiRegex, '').Length
            if ($len -gt $contentMaxWidth) { $contentMaxWidth = $len }
        }

        $minWidthRequired = $contentMaxWidth + ($Padding * 2) + 2
        if ($Title.Length + 4 -gt $minWidthRequired) { $minWidthRequired = $Title.Length + 4 }

        if ($Width -le 0) {
            $termWidth = try { [Console]::WindowWidth } catch { 80 }
            $Width = [Math]::Max($minWidthRequired, [Math]::Min(132, ($termWidth - 2)))
        } elseif ($Width -lt $minWidthRequired) {
            $Width = $minWidthRequired
        }

        $innerWidth = $Width - 2

        if (![string]::IsNullOrWhiteSpace($Title)) {
            $titleStr = " $Title "
            $insertPos = 1
            if ($Alignment -eq 'Center') { $insertPos = [math]::Floor(($innerWidth - $titleStr.Length) / 2) }
            elseif ($Alignment -eq 'Right') { $insertPos = $innerWidth - $titleStr.Length - 1 }

            $leftRuleCount = [Math]::Max(0, $insertPos)
            $rightRuleCount = [Math]::Max(0, $innerWidth - ($leftRuleCount + $titleStr.Length))

            $rawLeft = $ui.TopLeft + ($ui.Horizontal * $leftRuleCount)
            $rawRight = ($ui.Horizontal * $rightRuleCount) + $ui.TopRight

            $tLeft = if ($Width -gt 1) { ($leftRuleCount + 1) / [double]$Width } else { 0.5 }
            $tRight = if ($Width -gt 1) { ($Width - $rightRuleCount - 1) / [double]$Width } else { 0.5 }

            $coloredLeft = Format-GradientString -Text $rawLeft -Start $orange -End (Get-InterpolatedRgb -Start $orange -End $offBlack -T $tLeft)
            $coloredTitle = (& $palette.Apply $titleStr $titleCode)
            $coloredRight = Format-GradientString -Text $rawRight -Start (Get-InterpolatedRgb -Start $orange -End $offBlack -T $tRight) -End $offBlack
            $coloredTop = "$coloredLeft$coloredTitle$coloredRight"
        } else {
            $rawTop = $ui.TopLeft + ($ui.Horizontal * $innerWidth) + $ui.TopRight
            $coloredTop = Format-GradientString -Text $rawTop -Start $orange -End $offBlack
        }

        $rawBottom = $ui.BottomLeft + ($ui.Horizontal * $innerWidth) + $ui.BottomRight
        $coloredBottom = Format-GradientString -Text $rawBottom -Start $orange -End $offBlack

        $coloredLeftVert = Format-AnsiText -Text $ui.Vertical -Color $orange
        $coloredRightVert = Format-AnsiText -Text $ui.Vertical -Color $offBlack

        $outLines = [System.Collections.Generic.List[string]]::new()
        $outLines.Add($coloredTop)

        $padStr = ' ' * $Padding
        $contentFillWidth = $innerWidth - ($Padding * 2)

        foreach ($line in $internalContent) {
            $formattedLine = Format-TuiString -Text $line -Width $contentFillWidth -Alignment $Alignment
            $outLines.Add(-join ($coloredLeftVert, $padStr, $formattedLine, $padStr, $coloredRightVert))
        }

        $outLines.Add($coloredBottom)
        Write-Output ($outLines -join [Environment]::NewLine)
    }
}
