# ==============================================================================
# File: New-TrailingLog.ps1 (Public Cmdlet)
# ==============================================================================
function New-TrailingLog {
    <#
    .SYNOPSIS
        The New-TrailingLog pipeline processes log collections into trailing outputs.
    .DESCRIPTION
        The New-TrailingLog pipeline processes log collections into trailing outputs.
        Designed to accept String[], List[string], or Queue[string].
    .PARAMETER LogData
        The raw collection of data representing the execution log.
    .PARAMETER MaxLines
        Specifies the exact numerical height of the output block.
    .PARAMETER ColorMode
        Color mode formatting across the lines: Solid, GradientFade.
    .PARAMETER GradientStart
        TrueColor RGB array for the oldest visible entry. Default is 60,60,60.
    .PARAMETER GradientEnd
        TrueColor RGB array for the newest entry. Default is 255,255,255.
    .PARAMETER SolidColor
        ANSI SGR code string used if ColorMode is Solid. Default is 38;5;255.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [Object]$LogData,

        [Parameter(Mandatory = $false)]
        [int]$MaxLines = 5,

        [Parameter(Mandatory = $false)]
        [ValidateSet('Solid', 'GradientFade')]
        [string]$ColorMode = 'GradientFade',

        [Parameter(Mandatory = $false)]
        [int[]]$GradientStart = @(60, 60, 60), 

        [Parameter(Mandatory = $false)]
        [int[]]$GradientEnd = @(255, 255, 255), 

        [Parameter(Mandatory = $false)]
        [string]$SolidColor = "38;5;255"
    )

    process {
        $esc = [char]27
        $reset = "$esc[0m"

        $logArray = @($LogData)
        if ($logArray.Count -eq 0) { return "" }

        $startIndex = [math]::Max(0, $logArray.Count - $MaxLines)
        $displayLogs = $logArray[$startIndex..($logArray.Count - 1)]
        $count = $displayLogs.Count

        $halfCount = [math]::Floor($count / 2)
        $outLines = [System.Collections.Generic.List[string]]::new()

        for ($i = 0; $i -lt $count; $i++) {
            $line = $displayLogs[$i]
            if ([string]::IsNullOrWhiteSpace($line)) {
                $outLines.Add("")
                continue
            }

            if ($ColorMode -eq 'Solid') {
                $outLines.Add("$esc[$SolidColor`m$line$reset")
            }
            else {
                if ($i -lt ($count - $halfCount)) {
                    $fadeSteps = $count - $halfCount
                    $ratio = if ($fadeSteps -gt 1) { $i / ($fadeSteps - 1) } else { 1 }
                    $r = [math]::Round($GradientStart[0] + ($GradientEnd[0] - $GradientStart[0]) * $ratio)
                    $g = [math]::Round($GradientStart[1] + ($GradientEnd[1] - $GradientStart[1]) * $ratio)
                    $b = [math]::Round($GradientStart[2] + ($GradientEnd[2] - $GradientStart[2]) * $ratio)
                    $outLines.Add("$esc[38;2;$r;$g;$b`m$line$reset")
                } 
                else {
                    $r = $GradientEnd[0]; $g = $GradientEnd[1]; $b = $GradientEnd[2]
                    $outLines.Add("$esc[38;2;$r;$g;$b`m$line$reset")
                }
            }
        }

        Write-Output ($outLines -join [Environment]::NewLine)
    }
}
