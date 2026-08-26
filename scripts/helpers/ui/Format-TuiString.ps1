# ------------------------------------------------------------------------------
# FUNCTION: Format-TuiString
# ------------------------------------------------------------------------------
function Format-TuiString {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Text,

        [Parameter(Mandatory = $true)]
        [int]$Width,

        [Parameter(Mandatory = $false)]
        [ValidateSet('Left', 'Center', 'Right')]
        [string]$Alignment = 'Left',

        [Parameter(Mandatory = $false)]
        [char]$PadChar = ' '
    )

    process {
        $ansiRegex = [char]27 + '\[[0-9;]*[a-zA-Z]'
        $visibleLength = ($Text -replace $ansiRegex, '').Length

        if ($visibleLength -ge $Width) { return $Text }
        
        $padAmount = $Width - $visibleLength

        switch ($Alignment) {
            'Left' { return $Text + ([string]$PadChar * $padAmount) }
            'Right' { return ([string]$PadChar * $padAmount) + $Text }
            'Center' {
                $leftPad = [math]::Floor($padAmount / 2)
                $rightPad = [math]::Ceiling($padAmount / 2)
                return ([string]$PadChar * $leftPad) + $Text + ([string]$PadChar * $rightPad)
            }
        }
    }
}
