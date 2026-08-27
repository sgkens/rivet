<#
.SYNOPSIS
    Displays a resize-aware, keyboard-driven terminal menu with configurable description display modes.
.DESCRIPTION
    Redraws atomically when the terminal size or selection changes. Supports four description
    display types:
    - Card: Dedicated framed preview card spanning the full height of the menu with padded context.
    - Inline: Classic side-by-side dual-column list with bottom detail bar.
    - Minimal: Distraction-free single-column list with concise bottom status bar.
    - Pager: Expanded multi-line scrollable documentation viewport.
#>
function Get-SMenuTerminalSize {
    [CmdletBinding()]
    param()

    $width = try { [Console]::WindowWidth } catch { 120 }
    $height = try { [Console]::WindowHeight } catch { 30 }
    [pscustomobject]@{
        Width = [Math]::Max(24, $width)
        Height = [Math]::Max(10, $height)
    }
}

function Split-SMenuText {
    [CmdletBinding()]
    param(
        [AllowEmptyString()][string]$Text,
        [ValidateRange(1, [int]::MaxValue)][int]$Width
    )

    $lines = [System.Collections.Generic.List[string]]::new()
    foreach ($paragraph in ($Text -split '\r?\n')) {
        $remaining = $paragraph.Trim()
        if (-not $remaining.Length) { $lines.Add(''); continue }
        while ($remaining.Length -gt $Width) {
            $breakAt = $remaining.LastIndexOf(' ', $Width)
            if ($breakAt -lt 1) { $breakAt = $Width }
            $lines.Add($remaining.Substring(0, $breakAt).TrimEnd())
            $remaining = $remaining.Substring($breakAt).TrimStart()
        }
        $lines.Add($remaining)
    }
    return $lines.ToArray()
}

function Get-SMenuLayout {
    [CmdletBinding()]
    param(
        [ValidateRange(1, [int]::MaxValue)][int]$TerminalWidth,
        [ValidateRange(1, [int]::MaxValue)][int]$TerminalHeight,
        [ValidateRange(1, [int]::MaxValue)][int]$ItemCount,
        [ValidateRange(3, 100)][int]$ViewSize = 30,
        [ValidateSet('Inline', 'Minimal', 'Card', 'Pager')][string]$DescriptionDisplay = 'Card'
    )

    $frameWidth = [Math]::Max(22, [Math]::Min(132, $TerminalWidth - 2))
    $contentWidth = [Math]::Max(16, $frameWidth - 4)
    $wide = $contentWidth -ge 56
    $reservedRows = if ($wide -and ($DescriptionDisplay -in @('Card', 'Pager'))) { 6 } elseif ($wide) { 8 } else { 11 }
    $visibleItems = [Math]::Max(3, [Math]::Min([Math]::Min($ViewSize, $ItemCount), $TerminalHeight - $reservedRows))

    $labelWidth = if ($DescriptionDisplay -eq 'Minimal') {
        $contentWidth - 4
    } elseif ($DescriptionDisplay -in @('Card', 'Pager') -and $wide) {
        [Math]::Max(20, [int][Math]::Floor($contentWidth * 0.42))
    } elseif ($wide) {
        [Math]::Max(20, [int][Math]::Floor($contentWidth * 0.38))
    } else {
        $contentWidth - 4
    }

    $cardWidth = if ($wide -and ($DescriptionDisplay -in @('Card', 'Pager'))) {
        [Math]::Max(20, $contentWidth - $labelWidth - 3)
    } else {
        $contentWidth - 2
    }

    $descriptionWidth = if ($wide -and $DescriptionDisplay -eq 'Inline') {
        [Math]::Max(18, $contentWidth - $labelWidth - 5)
    } else {
        $contentWidth - 4
    }

    [pscustomobject]@{
        FrameWidth         = $frameWidth
        ContentWidth       = $contentWidth
        Wide               = $wide
        VisibleItems       = $visibleItems
        LabelWidth         = $labelWidth
        CardWidth          = $cardWidth
        DescriptionWidth   = $descriptionWidth
        DescriptionDisplay = $DescriptionDisplay
    }
}

function Show-SMenu {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][object[]]$Items,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Title,
        [ValidateRange(0, [int]::MaxValue)][int]$DefaultIndex = 0,
        [ValidateRange(3, 100)][int]$ViewSize = 30,
        [ValidateSet('Inline', 'Minimal', 'Card', 'Pager')][string]$DescriptionDisplay = 'Card'
    )

    if ([Console]::IsInputRedirected -or [Console]::IsOutputRedirected) {
        throw 'Show-SMenu requires an interactive terminal.'
    }
    if ($DefaultIndex -ge $Items.Count) { $DefaultIndex = 0 }

    $esc = [char]27
    $colors = [ordered]@{
        Reset      = "$esc[0m"
        Border     = "$esc[38;2;48;58;78m"
        Accent     = "$esc[1;38;2;0;210;255m"
        Secondary  = "$esc[38;2;255;70;180m"
        Text       = "$esc[38;2;224;230;240m"
        Muted      = "$esc[38;2;130;142;166m"
        Faint      = "$esc[38;2;82;94;118m"
        Selected   = "$esc[1;38;2;255;255;255m"
        Multi      = "$esc[1;38;2;196;112;255m"
        CardBorder = "$esc[38;2;255;130;0m"
        CardTitle  = "$esc[1;38;2;255;195;75m"
        Tag        = "$esc[38;2;0;200;255m"
    }

    $currentIndex = $DefaultIndex
    $currentDisplayMode = $DescriptionDisplay
    $pagerOffset = 0
    $topIndex = 0
    $lastWidth = -1
    $lastHeight = -1
    $needsRedraw = $true

    function Get-ItemTitle([object]$Item) {
        $label = [string]$Item.Label
        $multiProperty = $Item.PSObject.Properties['MultiAction']
        if ($null -ne $multiProperty -and [bool]$multiProperty.Value) { return "$label [MA]" }
        return $label
    }

    function Write-Frame([object]$Size) {
        $layout = Get-SMenuLayout -TerminalWidth $Size.Width -TerminalHeight $Size.Height -ItemCount $Items.Count -ViewSize $ViewSize -DescriptionDisplay $currentDisplayMode
        if ($currentIndex -lt $topIndex) { $topIndex = $currentIndex }
        if ($currentIndex -ge ($topIndex + $layout.VisibleItems)) { $topIndex = $currentIndex - $layout.VisibleItems + 1 }
        $topIndex = [Math]::Max(0, [Math]::Min($topIndex, [Math]::Max(0, $Items.Count - $layout.VisibleItems)))

        $inner = $layout.FrameWidth - 2
        $builder = [System.Text.StringBuilder]::new([Math]::Max(2048, $layout.FrameWidth * $Size.Height))
        $rule = [string]::new([char]0x2500, $inner)
        $orange = @(255, 130, 0)
        $offBlack = @(40, 44, 54)

        $topBorder = Format-GradientString -Text "┌$rule┐" -Start $orange -End $offBlack
        $midBorder = Format-GradientString -Text "├$rule┤" -Start $orange -End $offBlack
        $botBorder = Format-GradientString -Text "└$rule┘" -Start $orange -End $offBlack
        $leftVert = Format-AnsiText -Text '│' -Color $orange
        $rightVert = Format-AnsiText -Text '│' -Color $offBlack

        [void]$builder.Append("$esc[H$esc[2J")
        [void]$builder.AppendLine($topBorder)
        $titleRow = Pad-AnsiString -Text "$($colors.Accent) $Title $($colors.Reset)" -Width $inner -Align Left -Truncate
        [void]$builder.AppendLine("$leftVert$titleRow$rightVert")

        $modeTag = "[$currentDisplayMode]"
        $position = "$($currentIndex + 1)/$($Items.Count) $modeTag"
        $hintBudget = [Math]::Max(1, $inner - $position.Length - 1)
        $hint = Pad-AnsiString -Text "$($colors.Muted) ↑/↓/j/k navigate  pgup/pgdn/u/d page  enter/l select  tab mode  esc/q back$($colors.Reset)" -Width $hintBudget -Align Left -Truncate
        [void]$builder.AppendLine("$leftVert$hint $($colors.Faint)$position$($colors.Reset)$rightVert")
        [void]$builder.AppendLine($midBorder)

        $selectedItem = $Items[$currentIndex]
        $selectedDesc = if ($selectedItem.Description) { [string]$selectedItem.Description } else { 'No description provided.' }

        # Prepare description lines for Card / Pager modes
        $cardInnerWidth = [Math]::Max(8, $layout.CardWidth - 4)
        $cardDescLines = @(Split-SMenuText -Text $selectedDesc -Width $cardInnerWidth)

        for ($row = 0; $row -lt $layout.VisibleItems; $row++) {
            $itemIndex = $topIndex + $row
            $item = if ($itemIndex -lt $Items.Count) { $Items[$itemIndex] } else { $null }

            # Left cell (Option selector & title)
            $leftCell = ''
            if ($item) {
                $selected = ($itemIndex -eq $currentIndex)
                $titlePlain = Get-ItemTitle $item
                $multi = $titlePlain.EndsWith(' [MA]', [System.StringComparison]::Ordinal)
                $baseTitle = if ($multi) { $titlePlain.Substring(0, $titlePlain.Length - 5) } else { $titlePlain }
                $marker = if ($selected) { ' > ' } elseif ($row -eq 0 -and $topIndex -gt 0) { ' ▲ ' } elseif ($row -eq ($layout.VisibleItems - 1) -and ($topIndex + $layout.VisibleItems) -lt $Items.Count) { ' ▼ ' } else { '   ' }
                $titleColor = if ($selected) { $colors.Selected } else { $colors.Text }
                $titleText = "$titleColor$baseTitle$($colors.Reset)"
                if ($multi) { $titleText += "$($colors.Multi) [MA]$($colors.Reset)" }
                $leftCell = Pad-AnsiString -Text "$marker$titleText" -Width ($layout.LabelWidth + 3) -Align Left -Truncate
            } else {
                $leftCell = ' ' * ($layout.LabelWidth + 3)
            }

            # Render row based on active DescriptionDisplay mode
            if ($layout.Wide -and $currentDisplayMode -in @('Card', 'Pager')) {
                # Right Card / Pager Box rendering spanning the full height of item rows
                $cardRowText = ''
                $cardRule = [string]::new([char]0x2500, [Math]::Max(1, $layout.CardWidth - 2))

                if ($row -eq 0) {
                    $hasMoreAbove = ($currentDisplayMode -eq 'Pager' -and $pagerOffset -gt 0)
                    $headerTag = if ($currentDisplayMode -eq 'Pager') { if ($hasMoreAbove) { ' DOCS PAGER ▲ ' } else { ' DOCS PAGER ' } } else { ' DETAILS ' }
                    $headRule = [string]::new([char]0x2500, [Math]::Max(1, $layout.CardWidth - $headerTag.Length - 4))
                    $cardRowText = "$($colors.CardBorder)╭─$($colors.CardTitle)$headerTag$($colors.CardBorder)$headRule╮$($colors.Reset)"
                } elseif ($row -eq ($layout.VisibleItems - 1)) {
                    $hasMoreBelow = ($currentDisplayMode -eq 'Pager' -and ($pagerOffset + $layout.VisibleItems - 2) -lt $cardDescLines.Count)
                    if ($hasMoreBelow) {
                        $footTag = ' ▼ MORE '
                        $footRule = [string]::new([char]0x2500, [Math]::Max(1, $layout.CardWidth - $footTag.Length - 3))
                        $cardRowText = "$($colors.CardBorder)╰$cardRule$($colors.CardTitle)$footTag$($colors.CardBorder)╯$($colors.Reset)"
                    } else {
                        $cardRowText = "$($colors.CardBorder)╰$cardRule╯$($colors.Reset)"
                    }
                } elseif ($row -eq 1) {
                    $itemHeader = "▶ $(Get-ItemTitle $selectedItem)"
                    $cardRowText = "$($colors.CardBorder)│$($colors.Reset) " + (Pad-AnsiString -Text "$($colors.Selected)$itemHeader$($colors.Reset)" -Width ($layout.CardWidth - 4) -Align Left -Truncate) + " $($colors.CardBorder)│$($colors.Reset)"
                } else {
                    $offset = if ($currentDisplayMode -eq 'Pager') { $pagerOffset } else { 0 }
                    $lineIdx = $row - 2 + $offset
                    $lineText = if ($lineIdx -lt $cardDescLines.Count) { $cardDescLines[$lineIdx] } else { '' }
                    $cardRowText = "$($colors.CardBorder)│$($colors.Reset) " + (Pad-AnsiString -Text "$($colors.Muted)$lineText$($colors.Reset)" -Width ($layout.CardWidth - 4) -Align Left -Truncate) + " $($colors.CardBorder)│$($colors.Reset)"
                }

                $combinedLine = Pad-AnsiString -Text "$leftCell $($colors.Faint)│$($colors.Reset) $cardRowText" -Width $inner -Align Left -Truncate
                [void]$builder.AppendLine("$leftVert$combinedLine$rightVert")

            } elseif ($layout.Wide -and $currentDisplayMode -eq 'Inline') {
                $descriptionProperty = if ($item) { $item.PSObject.Properties['Description'] } else { $null }
                $descText = if ($null -eq $descriptionProperty) { '' } else { [string]$descriptionProperty.Value }
                $descriptionCell = Pad-AnsiString -Text "$($colors.Muted)$descText$($colors.Reset)" -Width $layout.DescriptionWidth -Align Left -Truncate
                $line = Pad-AnsiString -Text "$leftCell  $descriptionCell" -Width $inner -Align Left -Truncate
                [void]$builder.AppendLine("$leftVert$line$rightVert")

            } else { # Minimal mode or narrow terminal
                $line = Pad-AnsiString -Text "$leftCell" -Width $inner -Align Left -Truncate
                [void]$builder.AppendLine("$leftVert$line$rightVert")
            }
        }

        # Render bottom details footer unless wide Card/Pager is already showing side card
        if (-not ($layout.Wide -and $currentDisplayMode -in @('Card', 'Pager'))) {
            [void]$builder.AppendLine($midBorder)
            $detailTitle = "DETAIL: $(Get-ItemTitle $selectedItem)"
            $detailLine = Pad-AnsiString -Text "$($colors.Secondary)$detailTitle$($colors.Reset)" -Width $inner -Align Left -Truncate
            [void]$builder.AppendLine("$leftVert$detailLine$rightVert")

            $detailLines = @(Split-SMenuText -Text $selectedDesc -Width ([Math]::Max(8, $inner - 4)))
            $detailRows = if ($currentDisplayMode -eq 'Minimal') {
                1
            } elseif ($currentDisplayMode -eq 'Pager') {
                [Math]::Min(5, [Math]::Max(1, $detailLines.Count))
            } else {
                [Math]::Min(3, [Math]::Max(1, $detailLines.Count))
            }

            for ($index = 0; $index -lt $detailRows; $index++) {
                $lineIdx = if ($currentDisplayMode -eq 'Pager') { $pagerOffset + $index } else { $index }
                $detailText = if ($lineIdx -lt $detailLines.Count) { $detailLines[$lineIdx] } else { '' }
                $detail = Pad-AnsiString -Text "$($colors.Muted)  $detailText$($colors.Reset)" -Width $inner -Align Left -Truncate
                [void]$builder.AppendLine("$leftVert$detail$rightVert")
            }
        }

        [void]$builder.AppendLine($botBorder)
        [Console]::Write($builder.ToString())
    }

    try {
        Hide-TerminalCursor
        [Console]::Write("$esc[?1000h$esc[?1002h$esc[?1006h")

        $displayModes = @('Card', 'Inline', 'Minimal', 'Pager')

        while ($true) {
            $size = Get-SMenuTerminalSize
            if ($size.Width -ne $lastWidth -or $size.Height -ne $lastHeight) {
                $lastWidth = $size.Width
                $lastHeight = $size.Height
                $needsRedraw = $true
            }
            if ($needsRedraw) { Write-Frame -Size $size; $needsRedraw = $false }
            if (-not [Console]::KeyAvailable) {
                [System.Threading.Thread]::Sleep(40)
                continue
            }
            $key = [Console]::ReadKey($true)
            $kChar = $key.KeyChar

            # 1. UP navigation (Arrow Up, Vim k/K)
            if ($key.Key -eq 'UpArrow' -or $kChar -in @('k', 'K')) {
                if ($currentIndex -gt 0) {
                    $currentIndex--
                    $pagerOffset = 0
                    $needsRedraw = $true
                }
                continue
            }

            # 2. DOWN navigation (Arrow Down, Vim j/J)
            if ($key.Key -eq 'DownArrow' -or $kChar -in @('j', 'J')) {
                if ($currentIndex -lt ($Items.Count - 1)) {
                    $currentIndex++
                    $pagerOffset = 0
                    $needsRedraw = $true
                }
                continue
            }

            # 3. PAGE UP navigation (PageUp, Vim u/U, b/B)
            if ($key.Key -eq 'PageUp' -or $kChar -in @('u', 'U', 'b', 'B')) {
                if ($currentDisplayMode -eq 'Pager' -and $pagerOffset -gt 0) {
                    $pagerOffset = [Math]::Max(0, $pagerOffset - [Math]::Max(1, $layout.VisibleItems - 2))
                } else {
                    $pageSize = [Math]::Max(1, $layout.VisibleItems)
                    $currentIndex = [Math]::Max(0, $currentIndex - $pageSize)
                    $pagerOffset = 0
                }
                $needsRedraw = $true
                continue
            }

            # 4. PAGE DOWN navigation (PageDown, Vim d, f/F, Spacebar)
            if ($key.Key -in @('PageDown', 'Spacebar') -or $kChar -in @('f', 'F')) {
                if ($currentDisplayMode -eq 'Pager') {
                    $pagerOffset += [Math]::Max(1, $layout.VisibleItems - 2)
                } else {
                    $pageSize = [Math]::Max(1, $layout.VisibleItems)
                    $currentIndex = [Math]::Min($Items.Count - 1, $currentIndex + $pageSize)
                    $pagerOffset = 0
                }
                $needsRedraw = $true
                continue
            }

            # 5. HOME / TOP (Home, Vim g)
            if ($key.Key -eq 'Home' -or $kChar -eq 'g') {
                $currentIndex = 0
                $pagerOffset = 0
                $needsRedraw = $true
                continue
            }

            # 6. END / BOTTOM (End, Vim G)
            if ($key.Key -eq 'End' -or $kChar -eq 'G') {
                $currentIndex = $Items.Count - 1
                $pagerOffset = 0
                $needsRedraw = $true
                continue
            }

            # 7. SELECT / ENTER (Enter, Arrow Right, Vim l/L)
            if ($key.Key -in @('Enter', 'RightArrow') -or $kChar -in @('l', 'L')) {
                return $Items[$currentIndex].Value
            }

            # 8. MODE SWITCH (Tab, Shift+Tab, m/M, d/D)
            if ($key.Key -eq 'Tab' -or $kChar -in @('m', 'M', 'd', 'D')) {
                $modeIdx = [Array]::IndexOf($displayModes, $currentDisplayMode)
                if ($key.Modifiers -band [System.ConsoleModifiers]::Shift) {
                    $modeIdx = if ($modeIdx -le 0) { $displayModes.Count - 1 } else { $modeIdx - 1 }
                } else {
                    $modeIdx = ($modeIdx + 1) % $displayModes.Count
                }
                $currentDisplayMode = $displayModes[$modeIdx]
                $pagerOffset = 0
                $needsRedraw = $true
                continue
            }

            # 9. BACK / QUIT / ESCAPE (Escape, Arrow Left, Vim h/H, q/Q)
            if ($key.Key -in @('Escape', 'LeftArrow') -or $kChar -in @('q', 'Q', 'h', 'H')) {
                if ($key.Key -eq 'Escape') {
                    # Differentiate standalone Escape key from multi-byte ANSI sequences
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
                            if ($currentDisplayMode -eq 'Pager' -and $pagerOffset -gt 0) {
                                $pagerOffset = [Math]::Max(0, $pagerOffset - 1)
                                $needsRedraw = $true
                            } elseif ($currentIndex -gt 0) {
                                $currentIndex--
                                $pagerOffset = 0
                                $needsRedraw = $true
                            }
                        } elseif ($seqStr -match '65;' -or $seqStr -match '\[B' -or $seqStr -match 'OB' -or $seqStr -match 'a') {
                            if ($currentDisplayMode -eq 'Pager' -and ($pagerOffset + $layout.VisibleItems - 2) -lt $cardDescLines.Count) {
                                $pagerOffset++
                                $needsRedraw = $true
                            } elseif ($currentIndex -lt ($Items.Count - 1)) {
                                $currentIndex++
                                $pagerOffset = 0
                                $needsRedraw = $true
                            }
                        }
                        [System.Threading.Thread]::Sleep(10)
                        while ([Console]::KeyAvailable) { $null = [Console]::ReadKey($true) }
                        continue
                    }
                }
                return $null
            }
        }
    } finally {
        [Console]::Write("$esc[?1000l$esc[?1002l$esc[?1006l")
        Show-TerminalCursor
        [Console]::ResetColor()
        [Console]::WriteLine('')
    }
}
