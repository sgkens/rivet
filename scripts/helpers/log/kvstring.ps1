function New-kvstring {
    <#
        Helper Function: kvstring|kvstr
        type: Advanced function
        ------------------
        Description: Converts a string with key-value pairs to a key-value string
        
        * Supports key-value pairs with or without a level prefix
        * Supports nested key-value pairs
        * Supports multiple key-value pairs per string
        
        Example Usage:
        $message = "This is a {kv:key=value} and {kv:key2=value2}"
        New-kvstring -String $message
    #>
    [CmdletBinding()]
    param(
        [parameter(Mandatory, Position = 0)]
        [string]$String
    )
    process {
        # safety check
        if ($null -eq (Get-Command "New-Kvinc" -ErrorAction SilentlyContinue)) {
            Write-Host "ckvstring: Missing dependency: kvinc"
            return 
        }

        $pattern = '\{((?<Level>prop|property|meta|metadata|confval|inf|err|wrn|api|git|value|type|key):)?kv:(?<Key>[^=]+)=(?<Value>.*?)\}'
        $finalString = $String

        # Get all matches first
        $allMatches = [regex]::Matches($finalString, $pattern)

        # Process matches from right to left to avoid index shifting issues
        for ($i = $allMatches.Count - 1; $i -ge 0; $i--) {
            $match = $allMatches[$i]
            $Level = $match.Groups['Level'].Value.Trim()
            $key = $match.Groups['Key'].Value
            $value = $match.Groups['Value'].Value.Trim()

            if([string]::IsNullOrEmpty($Level)) {
                $replacement = New-Kvinc -KeyName $key -KeyValue $value
            }else{
                $replacement = New-Kvinc -KeyName $key -KeyValue $value -Type $Level
            }
            
            $finalString = $finalString.Remove($match.Index, $match.Length).Insert($match.Index, $replacement)
        }

        return $finalString
    }
}

