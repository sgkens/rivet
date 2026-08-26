function Format-SplitPad {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$String,

        [char]$Separator = ' '
    )

    return ($String -split $Separator) -join ' '
}