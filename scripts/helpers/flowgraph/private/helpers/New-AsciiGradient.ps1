function New-AsciiGradient {
    <#
    .SYNOPSIS
        Renders a string with a 256-color ANSI gradient applied to the foreground or background.

    .DESCRIPTION
        New-AsciiGradient interpolates across a list of 256-color palette indices (steps) and
        applies the resulting per-character color as either a foreground (fg) or background (bg)
        ANSI escape sequence.

        Interpolation is performed in RGB space — each stop is converted to its true RGB value,
        colors are blended linearly between stops, then the nearest available 256-color palette
        entry is selected for each character.  This produces smooth, visually correct gradients
        regardless of where the stop indices sit in the palette.

    .PARAMETER Type
        'fg'  – gradient is applied to the text foreground color.
        'bg'  – gradient is applied to the text background color.

    .PARAMETER Steps
        An array of two or more integers (0–255) representing the 256-color palette indices that
        define the gradient stops.  Colors are evenly distributed across the length of the string.
        Example: @(196, 214, 226, 46)  (red → orange → yellow → green)

    .PARAMETER String
        The text to colorize.

    .PARAMETER Format
        One or more text-decoration attributes to apply on top of the gradient color.
        Accepted values (combinable):
        bold, dim, italic, underline, blink, rapidblink, inverse, hidden, strikethrough
        Example: -Format bold, italic

    .PARAMETER Reset
        If supplied, a reset escape sequence is appended after the last character so that
        subsequent terminal output is not affected.  Defaults to $true.

    .EXAMPLE
        New-AsciiGradient -Type fg -Steps @(196, 202, 208, 214, 220, 226) -String "Hello, World!"

    .EXAMPLE
        New-AsciiGradient -Type bg -Steps @(21, 57, 93, 129, 165, 201) -String "Gradient Background"

    .EXAMPLE
        # Bold italic rainbow foreground
        $banner = "=== PowerShell 256-Color Gradient Demo ==="
        New-AsciiGradient -Type fg -Steps @(196,202,226,46,51,21,93,201) -Format bold,italic -String $banner | Write-Host

    .NOTES
        Requires a terminal that supports 256-color ANSI escape codes (xterm-256color).
        Windows Terminal, VS Code integrated terminal, and most modern Unix terminals qualify.
        The legacy Windows Console Host (conhost.exe) on older Windows versions may not render
        256-color sequences correctly.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    [alias('ascgrd')]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('fg', 'bg')]
        [string] $Type,

        [Parameter(Mandatory)]
        [int[]] $Steps,

        [Parameter(Mandatory, ValueFromPipeline)]
        [AllowEmptyString()]
        [string] $String,

        [Parameter()]
        [ValidateSet('bold','dim','italic','underline','blink','rapidblink','inverse','hidden','strikethrough')]
        [string[]] $Format = @(),

        [bool] $Reset = $true
    )

    begin {
        # ── Build the full xterm-256 palette as RGB triples ──────────────────
        # Use a plain object array so inner int[] triples are NOT flattened.
        $script:_palette = New-Object 'object[]' 256

        # 0–15: system / named colours
        $sys = @(
            @(0,0,0),     @(128,0,0),   @(0,128,0),   @(128,128,0),
            @(0,0,128),   @(128,0,128), @(0,128,128), @(192,192,192),
            @(128,128,128),@(255,0,0),  @(0,255,0),   @(255,255,0),
            @(0,0,255),   @(255,0,255), @(0,255,255), @(255,255,255)
        )
        for ($n = 0; $n -lt 16; $n++) { $script:_palette[$n] = [int[]]$sys[$n] }

        # 16–231: 6×6×6 colour cube
        for ($n = 16; $n -lt 232; $n++) {
            $idx = $n - 16
            $b   = [int]($idx % 6)
            $g   = [int](($idx / 6) % 6)
            $r   = [int]($idx / 36)
            $toV = [scriptblock]{ param($v) if ($v -eq 0) { 0 } else { 55 + $v * 40 } }
            $script:_palette[$n] = [int[]]@((&$toV $r), (&$toV $g), (&$toV $b))
        }

        # 232–255: greyscale ramp
        for ($n = 232; $n -lt 256; $n++) {
            $grey = 8 + ($n - 232) * 10
            $script:_palette[$n] = [int[]]@($grey, $grey, $grey)
        }

        # ── Helper: find nearest palette index to an RGB triple ───────────────
        # We search ONLY indices 16–255 (the colour cube + greyscale ramp).
        # Indices 0–15 are "system colours" whose actual RGB values vary by
        # terminal theme — relying on them produces wildly wrong colours on
        # terminals that remap them (e.g. dark/light themes, Windows Console).
        function Find-NearestPaletteIndex ([int]$tr, [int]$tg, [int]$tb) {
            $bestIdx  = 16
            $bestDist = [int]::MaxValue
            for ($i = 16; $i -lt 256; $i++) {
                $dr = $script:_palette[$i][0] - $tr
                $dg = $script:_palette[$i][1] - $tg
                $db = $script:_palette[$i][2] - $tb
                $d  = $dr*$dr + $dg*$dg + $db*$db
                if ($d -lt $bestDist) {
                    $bestDist = $d
                    $bestIdx  = $i
                    if ($d -eq 0) { break }
                }
            }
            return $bestIdx
        }

        # ── Helper: get the stable RGB for a stop index ───────────────────────
        # If the caller passed a system colour (0–15) we resolve it to its
        # nearest cube/greyscale equivalent so the gradient source RGB is also
        # stable.  This means @(9,226) (system-red → yellow) works the same as
        # @(196,226) (cube-red → yellow).
        function Resolve-StopRGB ([int]$idx) {
            if ($idx -ge 16) { return [int[]]$script:_palette[$idx] }
            $sr = $script:_palette[$idx][0]
            $sg = $script:_palette[$idx][1]
            $sb = $script:_palette[$idx][2]
            $nearIdx = Find-NearestPaletteIndex $sr $sg $sb
            return [int[]]$script:_palette[$nearIdx]
        }
    }

    process {
        # ── Validate Steps ────────────────────────────────────────────────────
        if ($Steps.Count -lt 2) {
            throw [System.ArgumentException]::new('Steps must contain at least two color indices.')
        }
        foreach ($c in $Steps) {
            if ($c -lt 0 -or $c -gt 255) {
                throw [System.ArgumentOutOfRangeException]::new('Steps', "Color index $c is out of range (0-255).")
            }
        }

        # Edge-case: empty string
        if ([string]::IsNullOrEmpty($String)) { return $String }

        # ── Pre-convert all stop indices to stable RGB ────────────────────────
        # IMPORTANT: must use ArrayList + explicit append to prevent PowerShell
        # pipeline from flattening the inner @(r,g,b) arrays into a single flat list.
        $stopRGB = [System.Collections.ArrayList]::new()
        foreach ($s in $Steps) { [void]$stopRGB.Add((Resolve-StopRGB $s)) }

        $chars     = $String.ToCharArray()
        $len       = $chars.Length
        $segCount  = $Steps.Count - 1
        $result    = [System.Text.StringBuilder]::new($len * 20)

        # ANSI colour prefix  fg→ESC[38;5;<n>m   bg→ESC[48;5;<n>m
        $escPrefix = if ($Type -eq 'fg') { "`e[38;5;" } else { "`e[48;5;" }

        # SGR format codes (bold, italic, …)
        $formatMap = @{
            bold=1; dim=2; italic=3; underline=4; blink=5
            rapidblink=6; inverse=7; hidden=8; strikethrough=9
        }
        $formatPrefix = if ($Format.Count -gt 0) {
            $codes = ($Format | ForEach-Object { $formatMap[$_] }) -join ';'
            "`e[${codes}m"
        } else { '' }

        # ── Per-character colour mapping ──────────────────────────────────────
        for ($i = 0; $i -lt $len; $i++) {

            # t ∈ [0.0 … segCount] — position along the full gradient
            $t = if ($len -gt 1) { $i / ($len - 1) * $segCount } else { 0.0 }

            # Segment index + fractional progress within that segment
            $segRaw = [Math]::Floor($t)
            if ($segRaw -ge $segCount) {
                # Exactly at the last stop
                $seg  = $segCount - 1
                $frac = 1.0
            } else {
                $seg  = [int]$segRaw
                $frac = $t - $segRaw
            }

            # ── Interpolate in RGB space ──────────────────────────────────────
            $rgbA = [int[]]$stopRGB[$seg]
            $rgbB = [int[]]$stopRGB[$seg + 1]

            $tr = [int][Math]::Round($rgbA[0] + ($rgbB[0] - $rgbA[0]) * $frac)
            $tg = [int][Math]::Round($rgbA[1] + ($rgbB[1] - $rgbA[1]) * $frac)
            $tb = [int][Math]::Round($rgbA[2] + ($rgbB[2] - $rgbA[2]) * $frac)

            # ── Snap to nearest 256-colour palette entry ──────────────────────
            $color = Find-NearestPaletteIndex $tr $tg $tb

            [void]$result.Append("${formatPrefix}${escPrefix}${color}m$($chars[$i])")
        }

        if ($Reset) { [void]$result.Append("`e[0m") }

        return $result.ToString()
    }
}