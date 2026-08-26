function Get-ElapsedTime {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [timespan]$TimeSpan,
        [Parameter(Mandatory = $false)]
        [switch]$AsObject
    )
    if ($AsObject) {
        return $TimeSpan
    }else{
        return "Total seconds: $($TimeSpan.TotalSeconds)"
    }
}