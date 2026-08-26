# ------------------------------------------------------------------------------
# FUNCTION: Show-TerminalCursor
# ------------------------------------------------------------------------------
function Show-TerminalCursor {
    [CmdletBinding()]
    param ()
    process {
        $esc = [char]27
        Write-Host -NoNewline "$esc[?25h"
    }
}