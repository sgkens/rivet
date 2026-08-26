<#
.SYNOPSIS
  Colorize a string using ANSI escape sequences.
.DESCRIPTION
  The New-AsciiColor function takes a string and a color, and returns the string with the specified color.
.PARAMETER string
  The input string to be colorized.
.PARAMETER color
  The color to be applied to the string.
.PARAMETER bgcolor
  The background color to be applied to the string.
.PARAMETER padding
  The padding to be applied to the string.
.PARAMETER Format
  One or more text styles to apply: Bold, Dim, Italic, Underline, Blink, Reverse, Hidden, Strikethrough.
.EXAMPLE
  New-AsciiColor -string "Hello World" -color 1
  New-AsciiColor -string "Hello World" -color 1 -bgcolor 2
  New-AsciiColor -string "Hello World" -color 1 -Format Bold
  New-AsciiColor -string "Hello World" -color 1 -Format Bold,Underline,Italic
.OUTPUTS
  The colorized string.
.NOTES
  The available colors are from 0 to 255.
.LINK
  https://en.wikipedia.org/wiki/ANSI_escape_code
#>
Function New-AsciiColor() {
  [CmdletBinding()]
  [Alias('AsciiColor', 'csole')]
  [OutputType([string])]
  param(
    [parameter(mandatory = $true, Position = 0)]
    [string]$string,
    [parameter(mandatory = $false, Position = 1)]
    [int]$color = 15,
    [parameter(mandatory = $false)]
    [int]$bgcolor = 0,
    [parameter(mandatory = $false)]
    [int]$padding = 0,
    [parameter(mandatory = $false)]
    [ValidateSet('Bold', 'Dim', 'Italic', 'Underline', 'Blink', 'Reverse', 'Hidden', 'Strikethrough')]
    [string[]]$Format
  )
  Begin {
    $escapeSequence = [char]27
    $colorReset = "${escapeSequence}[0m"

    $styleCodes = @{
      Bold          = 1
      Dim           = 2
      Italic        = 3
      Underline     = 4
      Blink         = 5
      Reverse       = 7
      Hidden        = 8
      Strikethrough = 9
    }
  }
  process {
    $paddedString = "{0,-$padding}" -f $string

    # Build style prefix from any requested formats
    $stylePrefix = if ($PSBoundParameters.ContainsKey('Format')) {
      ($Format | ForEach-Object { "${escapeSequence}[$($styleCodes[$_])m" }) -join ''
    }
    else { '' }

    if ($PSVersionTable.PSVersion.Major -eq 5) {
      $colorString = "${stylePrefix}${escapeSequence}[38;5;${color}m${paddedString}${colorReset}"
      if ($bgcolor -ge 0) {
        $colorString = "${escapeSequence}[48;5;${bgcolor}m$colorString"
      }
      return $colorString
    }
    else {
      $colorString = "${stylePrefix}`e[38;5;${color}m${paddedString}`e[0m"
      if ($bgcolor -ge 0) {
        $colorString = "`e[48;5;${bgcolor}m$colorString"
      }
      return $colorString
    }
  }
}