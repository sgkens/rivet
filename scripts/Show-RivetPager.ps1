function Show-RivetPager {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string[]]$Lines,
        [string]$Title = 'RIVET HELP'
    )

    $offset = 0
    $lastWidth = -1
    $lastHeight = -1
    $renderLines = @()
    $esc = [char]27

    while ($true) {
        $width = [Math]::Max(30, [Console]::WindowWidth)
        $height = [Math]::Max(8, [Console]::WindowHeight)
        $contentWidth = [Math]::Max(20, $width - 4)
        $pageSize = [Math]::Max(1, $height - 4)

        if ($width -ne $lastWidth) {
            $wrapped = [System.Collections.Generic.List[string]]::new()
            foreach ($sourceLine in $Lines) {
                $plainLine = ([string]$sourceLine) -replace "$esc\[[0-?]*[ -/]*[@-~]", ''
                if ($plainLine.Length -eq 0) {
                    $wrapped.Add('')
                    continue
                }
                foreach ($line in @(Split-SMenuText -Text $plainLine -Width $contentWidth)) {
                    $wrapped.Add($line)
                }
            }
            $renderLines = $wrapped.ToArray()
            $lastWidth = $width
        }

        $maxOffset = [Math]::Max(0, $renderLines.Count - $pageSize)
        $offset = [Math]::Max(0, [Math]::Min($offset, $maxOffset))

        $lastHeight = $height

        $frame = [System.Text.StringBuilder]::new($width * $height)
        $innerWidth = $width - 2
        $position = if ($renderLines.Count) { " $([Math]::Min($offset + 1, $renderLines.Count))-$([Math]::Min($offset + $pageSize, $renderLines.Count))/$($renderLines.Count) " } else { ' 0/0 ' }
        $titleText = " $Title "
        $ruleWidth = [Math]::Max(0, $innerWidth - $titleText.Length - $position.Length)
        [void]$frame.Append((Format-AnsiText -Text "┌$titleText$('─' * $ruleWidth)$position┐" -Color @(48, 58, 78))).AppendLine()

        for ($row = 0; $row -lt $pageSize; $row++) {
            $index = $offset + $row
            $text = if ($index -lt $renderLines.Count) { [string]$renderLines[$index] } else { '' }
            if ($text.Length -gt $contentWidth) { $text = $text.Substring(0, $contentWidth) }
            $padded = $text.PadRight($contentWidth)
            [void]$frame.Append((Format-AnsiText -Text '│' -Color @(48, 58, 78)))
            [void]$frame.Append(' ').Append($padded).Append(' ')
            [void]$frame.Append((Format-AnsiText -Text '│' -Color @(48, 58, 78))).AppendLine()
        }

        $footer = ' arrows scroll  pgup/pgdn page  home/end jump  esc/q close '
        if ($footer.Length -gt $innerWidth) { $footer = ' arrows/page scroll  esc/q close ' }
        $footerRule = [Math]::Max(0, $innerWidth - $footer.Length)
        [void]$frame.Append((Format-AnsiText -Text "└$footer$('─' * $footerRule)┘" -Color @(48, 58, 78)))
        [Console]::Write("$esc[H$($frame.ToString())$esc[J")

        while (-not [Console]::KeyAvailable) {
            Start-Sleep -Milliseconds 40
            if ([Console]::WindowWidth -ne $width -or [Console]::WindowHeight -ne $height) { break }
        }
        if (-not [Console]::KeyAvailable) { continue }

        $key = [Console]::ReadKey($true)
        switch ($key.Key) {
            'UpArrow' { $offset = [Math]::Max(0, $offset - 1) }
            'DownArrow' { $offset = [Math]::Min($maxOffset, $offset + 1) }
            'PageUp' { $offset = [Math]::Max(0, $offset - $pageSize) }
            'PageDown' { $offset = [Math]::Min($maxOffset, $offset + $pageSize) }
            'Home' { $offset = 0 }
            'End' { $offset = $maxOffset }
            'Escape' { return }
            'Enter' { return }
            default { if ($key.KeyChar -eq 'q' -or $key.KeyChar -eq 'Q') { return } }
        }
    }
}
