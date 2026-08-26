# ------------------------------------------------------------------------------
# FUNCTION: Hide-TerminalCursor
# ------------------------------------------------------------------------------
function Hide-TerminalCursor {
    [CmdletBinding()]
    param ()
    process {
        $esc = [char]27
        Write-Host -NoNewline "$esc[?25l"
    }
}