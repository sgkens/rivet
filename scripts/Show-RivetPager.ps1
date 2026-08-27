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

    try {
        [Console]::Write("$esc[?1000h$esc[?1002h$esc[?1006h")

        while ($true) {
            $width = [Math]::Max(30, [Console]::WindowWidth)
            $height = [Math]::Max(8, [Console]::WindowHeight)
            $contentWidth = [Math]::Max(20, $width - 4)
            $pageSize = [Math]::Max(1, $height - 4)

            if ($width -ne $lastWidth) {
                $wrapped = [System.Collections.Generic.List[string]]::new()
                foreach ($sourceLine in $Lines) {
                    if ($null -eq $sourceLine -or $sourceLine.Length -eq 0) {
                        $wrapped.Add('')
                        continue
                    }
                    $str = [string]$sourceLine
                    if ($str -notmatch "$esc" -and $str.Length -gt $contentWidth) {
                        foreach ($subLine in @(Split-SMenuText -Text $str -Width $contentWidth)) {
                            $wrapped.Add($subLine)
                        }
                    } else {
                        $wrapped.Add($str)
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
            $orange = @(255, 130, 0)
            $offBlack = @(40, 44, 54)
            $position = if ($renderLines.Count) { " $([Math]::Min($offset + 1, $renderLines.Count))-$([Math]::Min($offset + $pageSize, $renderLines.Count))/$($renderLines.Count) " } else { ' 0/0 ' }
            $titleText = " $Title "
            $ruleWidth = [Math]::Max(0, $innerWidth - $titleText.Length - $position.Length)
            $rawTop = "┌$titleText$('─' * $ruleWidth)$position┐"
            [void]$frame.Append((Format-GradientString -Text $rawTop -Start $orange -End $offBlack)).AppendLine()

            $leftVert = Format-AnsiText -Text '│' -Color $orange
            $rightVert = Format-AnsiText -Text '│' -Color $offBlack

            for ($row = 0; $row -lt $pageSize; $row++) {
                $index = $offset + $row
                $text = if ($index -lt $renderLines.Count) { [string]$renderLines[$index] } else { '' }
                $padded = Pad-AnsiString -Text $text -Width $contentWidth -Align Left -Truncate
                [void]$frame.Append($leftVert)
                [void]$frame.Append(' ').Append($padded).Append(' ')
                [void]$frame.Append($rightVert).AppendLine()
            }

            $footer = ' ↑/↓/j/k scroll  pgup/pgdn/u/d page  g/G top/end  esc/q close '
            if ($footer.Length -gt $innerWidth) { $footer = ' arrows/vim scroll  esc/q close ' }
            $footerRule = [Math]::Max(0, $innerWidth - $footer.Length)
            $rawBottom = "└$footer$('─' * $footerRule)┘"
            [void]$frame.Append((Format-GradientString -Text $rawBottom -Start $orange -End $offBlack))
            [Console]::Write("$esc[H$($frame.ToString())$esc[J")

            while (-not [Console]::KeyAvailable) {
                [System.Threading.Thread]::Sleep(20)
                $curW = try { [Console]::WindowWidth } catch { $width }
                $curH = try { [Console]::WindowHeight } catch { $height }
                if ($curW -ne $width -or $curH -ne $height) {
                    [Console]::Write("$esc[2J$esc[3J$esc[H")
                    break
                }
            }
            if (-not [Console]::KeyAvailable) { continue }

            $key = [Console]::ReadKey($true)
            $kChar = $key.KeyChar

            # 1. UP (Arrow Up, Vim k/K)
            if ($key.Key -eq 'UpArrow' -or $kChar -in @('k', 'K')) {
                $offset = [Math]::Max(0, $offset - 1)
                continue
            }

            # 2. DOWN (Arrow Down, Vim j/J)
            if ($key.Key -eq 'DownArrow' -or $kChar -in @('j', 'J')) {
                $offset = [Math]::Min($maxOffset, $offset + 1)
                continue
            }

            # 3. PAGE UP (PageUp, Vim u/U, b/B)
            if ($key.Key -eq 'PageUp' -or $kChar -in @('u', 'U', 'b', 'B')) {
                $offset = [Math]::Max(0, $offset - $pageSize)
                continue
            }

            # 4. PAGE DOWN (PageDown, Vim d, f/F, Spacebar)
            if ($key.Key -in @('PageDown', 'Spacebar') -or $kChar -in @('d', 'D', 'f', 'F', ' ')) {
                $offset = [Math]::Min($maxOffset, $offset + $pageSize)
                continue
            }

            # 5. HOME / TOP (Home, Vim g)
            if ($key.Key -eq 'Home' -or $kChar -eq 'g') {
                $offset = 0
                continue
            }

            # 6. END / BOTTOM (End, Vim G)
            if ($key.Key -eq 'End' -or $kChar -eq 'G') {
                $offset = $maxOffset
                continue
            }

            # 7. CLOSE / QUIT / BACK (Escape, Enter, Left/Right, Vim q/Q, h/H, l/L)
            if ($key.Key -in @('Escape', 'Enter', 'LeftArrow', 'RightArrow') -or $kChar -in @('q', 'Q', 'h', 'H', 'l', 'L')) {
                if ($key.Key -eq 'Escape') {
                    $hasFollowup = $false
                    $seq = [System.Text.StringBuilder]::new()
                    $timer = [System.Diagnostics.Stopwatch]::StartNew()
                    while ($timer.ElapsedMilliseconds -lt 60) {
                        if ([Console]::KeyAvailable) {
                            $hasFollowup = $true
                            while ([Console]::KeyAvailable) {
                                $k = [Console]::ReadKey($true)
                                [void]$seq.Append($k.KeyChar)
                            }
                            break
                        }
                        [System.Threading.Thread]::Sleep(5)
                    }
                    $timer.Stop()

                    if ($hasFollowup) {
                        $seqStr = $seq.ToString()
                        if ($seqStr -match '64;' -or $seqStr -match '\[A' -or $seqStr -match 'OA' -or $seqStr -match '`') {
                            $offset = [Math]::Max(0, $offset - 1)
                        } elseif ($seqStr -match '65;' -or $seqStr -match '\[B' -or $seqStr -match 'OB' -or $seqStr -match 'a') {
                            $offset = [Math]::Min($maxOffset, $offset + 1)
                        }
                        [System.Threading.Thread]::Sleep(10)
                        while ([Console]::KeyAvailable) {
                            $null = [Console]::ReadKey($true)
                        }
                        continue
                    }
                }
                return
            }
        }
    } finally {
        [Console]::Write("$esc[?1000l$esc[?1002l$esc[?1006l")
    }
}
