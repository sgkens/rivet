# ------------------------------------------------------------------------------
# FUNCTION: Join-TuiBlock
# ------------------------------------------------------------------------------
function Join-TuiBlock {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$LeftBlock,

        [Parameter(Mandatory = $true)]
        [string]$RightBlock,

        [Parameter(Mandatory = $false)]
        [int]$Padding = 4
    )

    process {
        $ansiRegex = [char]27 + '\[[0-9;]*[a-zA-Z]'
        
        $leftLines = $LeftBlock -split '\r?\n'
        $rightLines = $RightBlock -split '\r?\n'
        $maxLines = [math]::Max($leftLines.Count, $rightLines.Count)

        $leftMaxWidth = 0
        foreach ($line in $leftLines) {
            $len = ($line -replace $ansiRegex, '').Length
            if ($len -gt $leftMaxWidth) { $leftMaxWidth = $len }
        }

        $outLines = [System.Collections.Generic.List[string]]::new()
        $padStr = ' ' * $Padding

        for ($i = 0; $i -lt $maxLines; $i++) {
            $l = if ($i -lt $leftLines.Count) { $leftLines[$i] } else { '' }
            $r = if ($i -lt $rightLines.Count) { $rightLines[$i] } else { '' }

            $lFormatted = Format-TuiString -Text $l -Width $leftMaxWidth -Alignment Left
            $outLines.Add( -join ($lFormatted, $padStr, $r))
        }

        Write-Output ($outLines -join [Environment]::NewLine)
    }
}