# ------------------------------------------------------------------------------
# HELPER: Get-TerminalBg
# ------------------------------------------------------------------------------
function Get-TerminalBg {
    [CmdletBinding()]
    param ()
    
    process {
        # Dynamically query the host's current background color and map to ANSI SGR background codes
        $color = [Console]::BackgroundColor

        switch ($color) {
            'Black' { return '40' }
            'DarkRed' { return '41' }
            'DarkGreen' { return '42' }
            'DarkYellow' { return '43' }
            'DarkBlue' { return '44' }
            'DarkMagenta' { return '45' }
            'DarkCyan' { return '46' }
            'Gray' { return '47' }
            
            'DarkGray' { return '100' }
            'Red' { return '101' }
            'Green' { return '102' }
            'Yellow' { return '103' }
            'Blue' { return '104' }
            'Magenta' { return '105' }
            'Cyan' { return '106' }
            'White' { return '107' }
            
            default { return '40' } # Fallback to standard black
        }
    }
}