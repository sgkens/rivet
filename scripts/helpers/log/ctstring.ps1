function New-CTString {
    <#
        Helper Function: ctstring|ctstr|colorstring
        type: Advanced function
        ------------------
        Description: Converts a string with color codes to a colored string
        
        * Supports standard and 256 color palettes
        * Supports bold, italic, and underline
        * Supports nested color codes
        * Supports multiple color codes per string
        
        Example Usage:
        $message = "This is a {ct:cyan:cyan text}"
        New-CtString -String $message
    #>
    [CmdletBinding()]
    [Alias('ctstr', 'ctstring', 'colorstring')]
    param(
        [parameter(Mandatory, Position = 0)]
        [string]$String
    )

    process {

        # Define standard 3/4-bit color map (Standard ANSI) light and dark variants
        $stdColors = @{
            'black' = '30'
            'white' = '37'; 
            'gray' = '97'; 'lightgray' = '37'
            'red' = '31'; 'lightred' = '91'
            'green' = '32'; 'lightgreen' = '92'
            'yellow' = '33'; 'lightyellow' = '93'
            'blue' = '34'; 'lightblue' = '94'
            'magenta' = '35'; 'lightmagenta' = '95'
            'cyan' = '36'; 'lightcyan' = '96'
            'default' = '39'
        }

        # Regex Pattern
        # Matches: {ct:color:flags:message} or {ct:color:message}
        # Flags are optional (u, b, i)
        $pattern = '(?i)\{ct:(?<Color>[^:{}]+)(?::(?<Flags>[ubi](?::[ubi])*))?:(?<String>.*?)\}'

        $finalString = $String
        $ESC = [char]27

        # Get all matches
        $allMatches = [regex]::Matches($finalString, $pattern)

        # Process right-to-left to prevent index shifting
        for ($i = $allMatches.Count - 1; $i -ge 0; $i--) {
            $match = $allMatches[$i]
            
            # -- Extract Raw Values --
            $rawColor = $match.Groups['Color'].Value.ToLower()
            $content = $match.Groups['String'].Value
            $flagsStr = $match.Groups['Flags'].Value

            # -- Build ANSI Code List --
            $codes = [System.Collections.Generic.List[string]]::new()

            # A. Handle Flags (Bold, Underline, Italic)
            if ($flagsStr -match 'b') { $codes.Add('1') } # Bold
            if ($flagsStr -match 'i') { $codes.Add('3') } # Italic
            if ($flagsStr -match 'u') { $codes.Add('4') } # Underline

            # B. Handle Color
            if ($rawColor -match '^\d+$') {
                # Logic: 256 Color Palette (ID 0-255)
                # ANSI Format: 38;5;<n>
                $codes.Add("38;5;$rawColor")
            }
            elseif ($stdColors.ContainsKey($rawColor)) {
                # Logic: Standard Named Color
                $codes.Add($stdColors[$rawColor])
            }
            else {
                # Fallback if color name is unknown (Default to white/default)
                $codes.Add('39') 
            }

            # -- Construct Replacement String --
            # Format: <ESC>[<codes>m<Content><ESC>[0m
            $ansiSequence = "$ESC[" + ($codes -join ';') + "m"
            $replacement = "$ansiSequence$content$ESC[0m"

            # -- Replace in original string --
            $finalString = $finalString.Remove($match.Index, $match.Length).Insert($match.Index, $replacement)
        }

        return $finalString
    }
}

# Example Usage:
$message = "This is a {ct:cyan:cyan text}"
New-CtString -String $message