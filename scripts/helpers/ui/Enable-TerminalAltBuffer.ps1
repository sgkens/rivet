# ------------------------------------------------------------------------------
# FUNCTION: Enable-TerminalAltBuffer
# ------------------------------------------------------------------------------
function Enable-TerminalAltBuffer {
    [CmdletBinding()]
    param ()
    process {
        $esc = [char]27
        # Switch to alternate screen buffer
        Write-Host -NoNewline "$esc[?1049h"
    }
}