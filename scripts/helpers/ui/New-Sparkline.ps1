# ------------------------------------------------------------------------------
# FUNCTION: New-Sparkline
# ------------------------------------------------------------------------------
function New-Sparkline {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [double[]]$Data,

        [Parameter(Mandatory = $false)]
        [hashtable]$ColorPalette = @{},

        [Parameter(Mandatory = $false)]
        [ValidateSet('Solid', 'Gradient')]
        [string]$ColorMode = 'Solid',

        [Parameter(Mandatory = $false)]
        [int[]]$GradientStart = @(60, 60, 60),

        [Parameter(Mandatory = $false)]
        [int[]]$GradientEnd = @(255, 255, 255)
    )

    process {
        if ($Data.Count -eq 0) { return "" }
        
        $palette = Get-TerminalPalette -ColorPalette $ColorPalette -ColorMode $ColorMode -GradientStart $GradientStart -GradientEnd $GradientEnd -CurrentValue 100
        $blocks = @(' ', '▂', '▃', '▄', '▅', '▆', '▇', '█')
        
        $min = ($Data | Measure-Object -Minimum).Minimum
        $max = ($Data | Measure-Object -Maximum).Maximum
        $range = $max - $min
        if ($range -eq 0) { $range = 1 }

        $outChars = [System.Collections.Generic.List[string]]::new()

        for ($i = 0; $i -lt $Data.Count; $i++) {
            $normalized = ($Data[$i] - $min) / $range
            $index = [math]::Round($normalized * ($blocks.Count - 1))
            $char = $blocks[$index]

            $code = $null
            if ($ColorMode -eq 'Solid') {
                $code = (& $palette.GetStaticColor 'Fill')
                if ($null -eq $code) { $code = "38;5;255" }
            }
            else {
                $code = (& $palette.GetFillColor $i $Data.Count)
            }

            $outChars.Add((& $palette.Apply $char $code))
        }

        Write-Output (-join $outChars)
    }
}