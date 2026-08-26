# ==============================================================================
# File: Get-TerminalUI.ps1 (Private Helper)
# ==============================================================================
function Get-TerminalUI {
    <#
    .SYNOPSIS
        Generates structured TUI components based on the requested BorderStyle.
    .DESCRIPTION
        Returns a PSCustomObject containing the structural characters for borders.
    .PARAMETER BorderStyle
        The layout style of the border: None, Thin, Double, Rounded.
    #>
    param (
        [ValidateSet('None', 'Thin', 'Double', 'Rounded')]
        [string]$BorderStyle = 'None'
    )
    
    $ui = [PSCustomObject]@{
        TopLeft     = ''
        TopRight    = ''
        BottomLeft  = ''
        BottomRight = ''
        Horizontal  = ''
        Vertical    = ''
        HasBorder   = $false
    }

    switch ($BorderStyle) {
        'Thin' {
            $ui.TopLeft     = '┌'
            $ui.TopRight    = '┐'
            $ui.BottomLeft  = '└'
            $ui.BottomRight = '┘'
            $ui.Horizontal  = '─'
            $ui.Vertical    = '│'
            $ui.HasBorder   = $true
        }
        'Double' {
            $ui.TopLeft     = '╔'
            $ui.TopRight    = '╗'
            $ui.BottomLeft  = '╚'
            $ui.BottomRight = '╝'
            $ui.Horizontal  = '═'
            $ui.Vertical    = '║'
            $ui.HasBorder   = $true
        }
        'Rounded' {
            $ui.TopLeft     = '╭'
            $ui.TopRight    = '╮'
            $ui.BottomLeft  = '╰'
            $ui.BottomRight = '╯'
            $ui.Horizontal  = '─'
            $ui.Vertical    = '│'
            $ui.HasBorder   = $true
        }
    }
    return $ui
}
