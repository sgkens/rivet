# ------------------------------------------------------------------------------
# FUNCTION: New-TuiPanel
# ------------------------------------------------------------------------------
function New-TuiPanel {
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
        [string]$BorderStyle = 'Thin',

        [Parameter(Mandatory=$false)]
        [hashtable]$ColorPalette = @{ Border = "38;5;240"; Title = "38;5;255" },

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
        $borderCode = (& $palette.GetStaticColor 'Border')
        $titleCode = (& $palette.GetStaticColor 'Title')

        $ansiRegex = [char]27 + '\[[0-9;]*[a-zA-Z]'
        $contentMaxWidth = 0
        
        foreach ($line in $internalContent) {
            $len = ($line -replace $ansiRegex, '').Length
            if ($len -gt $contentMaxWidth) { $contentMaxWidth = $len }
        }

        $minWidthRequired = $contentMaxWidth + ($Padding * 2) + 2
        if ($Title.Length + 4 -gt $minWidthRequired) { $minWidthRequired = $Title.Length + 4 }

        if ($Width -le 0) {
            $Width = $minWidthRequired
        } elseif ($Width -lt $minWidthRequired) {
            $Width = $minWidthRequired
        }

        $innerWidth = $Width - 2
        $horizontalCount = $innerWidth

        $topLine = $ui.Horizontal * $horizontalCount
        if (![string]::IsNullOrWhiteSpace($Title)) {
            $titleStr = " $Title "
            $insertPos = 1
            if ($Alignment -eq 'Center') { $insertPos = [math]::Floor(($innerWidth - $titleStr.Length) / 2) }
            elseif ($Alignment -eq 'Right') { $insertPos = $innerWidth - $titleStr.Length - 1 }
            
            $coloredTitle = (& $palette.Apply $titleStr $titleCode)
            $topLine = $topLine.Remove($insertPos, $titleStr.Length).Insert($insertPos, $coloredTitle)
        }

        $coloredTop = (& $palette.Apply $ui.TopLeft $borderCode) + $topLine + (& $palette.Apply $ui.TopRight $borderCode)
        $coloredBottom = (& $palette.Apply ($ui.BottomLeft + ($ui.Horizontal * $horizontalCount) + $ui.BottomRight) $borderCode)
        $coloredVert = (& $palette.Apply $ui.Vertical $borderCode)

        $outLines = [System.Collections.Generic.List[string]]::new()
        $outLines.Add($coloredTop)

        $padStr = ' ' * $Padding
        $contentFillWidth = $innerWidth - ($Padding * 2)

        foreach ($line in $internalContent) {
            $formattedLine = Format-TuiString -Text $line -Width $contentFillWidth -Alignment $Alignment
            $outLines.Add(-join ($coloredVert, $padStr, $formattedLine, $padStr, $coloredVert))
        }

        $outLines.Add($coloredBottom)
        Write-Output ($outLines -join [Environment]::NewLine)
    }
}
