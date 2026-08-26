function Test-ContainsKey {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [psobject]$Object,

        [Parameter(Mandatory = $true)]
        [string]$Key
    )

    [bool]$result = $false
    switch ($Object.GetType().Name) {
        'Hashtable' {
            $result = $Object.ContainsKey($Key)
        }
        'PSCustomObject' {
            $result = $Object.psobject.Properties.Name -contains $Key
        }
        'Object[]' {
            $result = $Object.Where({ $_ -is [pscustomobject] -and $_.psobject.Properties.Name -contains $Key })
        }
        default {
            $result = $Object.psobject.Properties.Name -contains $Key
        }
    }
    return $result
}