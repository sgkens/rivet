# ------------------------------------------------------------------------------
# FUNCTION: Disable-TerminalAltBuffer
# ------------------------------------------------------------------------------
function Disable-TerminalAltBuffer {
    [CmdletBinding()]
    param ()
    process {
        $esc = [char]27
        # Return to main screen buffer
        Write-Host -NoNewline "$esc[?1049l"
    }
}