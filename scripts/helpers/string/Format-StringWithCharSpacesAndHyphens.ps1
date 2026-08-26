function Format-StringWithCharSpacesAndHyphens {
    <#
    .SYNOPSIS
    Formats a string by splitting words into individual characters separated by spaces,
    and replacing original word-separating spaces with hyphens.
    .DESCRIPTION
    This function takes an input string, splits it into words based on spaces.
    For each word, it then splits the word into its individual characters and
    rejoins them with spaces in between (e.g., "WORD" becomes "W O R D").
    Finally, the original spaces between words are replaced with hyphens.
    .PARAMETER InputString
    The string to be formatted.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [string]$InputString
    )

    begin {
        $processedWords = @()
    }

    process {
        $words = $InputString.Split(' ', [System.StringSplitOptions]::RemoveEmptyEntries)

        foreach ($word in $words) {
            $characters = $word.ToCharArray()
            $charSpacedWord = ($characters -join ' ')
            $processedWords += $charSpacedWord
        }
    }

    end {
        $finalFormattedString = ($processedWords -join ' - ')
        return $finalFormattedString
    }
}
