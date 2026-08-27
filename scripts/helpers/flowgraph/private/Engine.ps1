#region ─── UI / Theme Definitions ───────────────────────────────────────────

$script:FlowGraphUi = [pscustomobject]@{
    BoxStyles = @{
        Single  = @{
            TL = '┌'; TR = '┐'; BL = '└'; BR = '┘'
            H  = '─'; V  = '│'
            TM = '┬'; BM = '┴'; LM = '├'; RM = '┤'; C = '┼'
        }
        Double  = @{
            TL = '╔'; TR = '╗'; BL = '╚'; BR = '╝'
            H  = '═'; V  = '║'
            TM = '╦'; BM = '╩'; LM = '╠'; RM = '╣'; C = '╬'
        }
        Rounded = @{
            TL = '╭'; TR = '╮'; BL = '╰'; BR = '╯'
            H  = '─'; V  = '│'
            TM = '┬'; BM = '┴'; LM = '├'; RM = '┤'; C = '┼'
        }
        Heavy   = @{
            TL = '┏'; TR = '┓'; BL = '┗'; BR = '┛'
            H  = '━'; V  = '┃'
            TM = '┳'; BM = '┻'; LM = '┣'; RM = '┫'; C = '╋'
        }
        Ascii   = @{
            TL = '+'; TR = '+'; BL = '+'; BR = '+'
            H  = '-'; V  = '|'
            TM = '+'; BM = '+'; LM = '+'; RM = '+'; C = '+'
        }
    }
    NodeTypeColors = @{
        Default  = "`e[0m"
        Start    = "`e[92m"
        End      = "`e[91m"
        Process  = "`e[96m"
        Decision = "`e[93m"
        IO       = "`e[95m"
        Error    = "`e[31m"
        Warning  = "`e[33m"
        Info     = "`e[34m"
        Success  = "`e[32m"
    }
    ConnectorStyles = @{
        Arrow     = @{ Down = '▼'; Right = '▶'; Left = '◀'; Up = '▲'; Line = '│'; HLine = '─' }
        ArrowThin = @{ Down = '↓'; Right = '→'; Left = '←'; Up = '↑'; Line = '│'; HLine = '─' }
        Dot       = @{ Down = '•'; Right = '•'; Left = '•'; Up = '•'; Line = '╎'; HLine = '╌' }
        Ascii     = @{ Down = 'v'; Right = '>'; Left = '<'; Up = '^'; Line = '|'; HLine = '-' }
    }
    Title = @{
        Accent = "`e[96m"
        Bold   = "`e[1m"
        Reset  = "`e[0m"
    }
}

$script:FlowGraphUiActive = $script:FlowGraphUi

function script:Merge-FlowGraphHashTable {
    param(
        [hashtable]$Base,
        [hashtable]$Override
    )

    $result = @{}
    foreach ($key in $Base.Keys) {
        $value = $Base[$key]
        if ($value -is [hashtable]) {
            $result[$key] = script:Merge-FlowGraphHashTable -Base $value -Override @{}
        } elseif ($value -is [System.Collections.IDictionary]) {
            $result[$key] = @{} + $value
        } else {
            $result[$key] = $value
        }
    }

    foreach ($key in $Override.Keys) {
        $value = $Override[$key]
        if ($result.ContainsKey($key) -and $result[$key] -is [hashtable] -and $value -is [hashtable]) {
            $result[$key] = script:Merge-FlowGraphHashTable -Base $result[$key] -Override $value
        } elseif ($value -is [System.Collections.IDictionary]) {
            $result[$key] = @{} + $value
        } else {
            $result[$key] = $value
        }
    }

    return $result
}

function script:Resolve-FlowGraphUi {
    param([hashtable]$Overrides)

    $ui = [pscustomobject]@{
        BoxStyles      = @{} + $script:FlowGraphUi.BoxStyles
        NodeTypeColors = @{} + $script:FlowGraphUi.NodeTypeColors
        ConnectorStyles = @{} + $script:FlowGraphUi.ConnectorStyles
        Title          = @{} + $script:FlowGraphUi.Title
    }

    if ($Overrides) {
        foreach ($key in $Overrides.Keys) {
            switch ($key) {
                'BoxStyles'      { $ui.BoxStyles = script:Merge-FlowGraphHashTable -Base $ui.BoxStyles -Override $Overrides[$key] }
                'NodeTypeColors' { $ui.NodeTypeColors = script:Merge-FlowGraphHashTable -Base $ui.NodeTypeColors -Override $Overrides[$key] }
                'ConnectorStyles' { $ui.ConnectorStyles = script:Merge-FlowGraphHashTable -Base $ui.ConnectorStyles -Override $Overrides[$key] }
                'Title'          { $ui.Title = script:Merge-FlowGraphHashTable -Base $ui.Title -Override $Overrides[$key] }
                default          { $ui | Add-Member -NotePropertyName $key -NotePropertyValue $Overrides[$key] -Force }
            }
        }
    }

    return $ui
}

function script:ConvertTo-FlowGraphRgb {
    param([object]$Value)

    if ($null -eq $Value) { return $null }

    if ($Value -is [string]) {
        $text = $Value.Trim()
        if ($text.StartsWith('#')) {
            $text = $text.Substring(1)
        }

        if ($text -match '^[0-9A-Fa-f]{6}$') {
            return @(
                [Convert]::ToInt32($text.Substring(0, 2), 16)
                [Convert]::ToInt32($text.Substring(2, 2), 16)
                [Convert]::ToInt32($text.Substring(4, 2), 16)
            )
        }

        if ($text -match '^\d{1,3}(,\d{1,3}){2}$') {
            return @($text.Split(',') | ForEach-Object { [int]$_ })
        }
    }

    if ($Value -is [System.Array] -and $Value.Count -ge 3) {
        return @([int]$Value[0], [int]$Value[1], [int]$Value[2])
    }

    return $null
}

function script:New-FlowGraphAnsiColor {
    param(
        [object]$Color,
        [switch]$Background
    )

    $rgb = script:ConvertTo-FlowGraphRgb -Value $Color
    if (-not $rgb) { return '' }

    $channel = if ($Background) { 48 } else { 38 }
    return "`e[$channel;2;$($rgb[0]);$($rgb[1]);$($rgb[2])m"
}

function script:Blend-FlowGraphRgb {
    param(
        [object]$Start,
        [object]$End,
        [double]$T
    )

    $startRgb = script:ConvertTo-FlowGraphRgb -Value $Start
    $endRgb   = script:ConvertTo-FlowGraphRgb -Value $End
    if (-not $startRgb -or -not $endRgb) { return $null }

    return @(
        [int][Math]::Round($startRgb[0] + ($endRgb[0] - $startRgb[0]) * $T)
        [int][Math]::Round($startRgb[1] + ($endRgb[1] - $startRgb[1]) * $T)
        [int][Math]::Round($startRgb[2] + ($endRgb[2] - $startRgb[2]) * $T)
    )
}

function script:Get-FlowGraphVisibleLength {
    param([string]$Text)

    if ([string]::IsNullOrEmpty($Text)) { return 0 }

    $cmd = Get-Command Get-ClapVisibleLength -ErrorAction SilentlyContinue
    if ($cmd) {
        return Get-ClapVisibleLength -Text $Text
    }

    return $Text.Length
}

function script:Format-FlowGraphGradientText {
    param(
        [string]$Text,
        [object]$Start,
        [object]$End
    )

    $startRgb = script:ConvertTo-FlowGraphRgb -Value $Start
    $endRgb   = script:ConvertTo-FlowGraphRgb -Value $End
    if (-not $startRgb -or -not $endRgb -or [string]::IsNullOrEmpty($Text)) {
        return $Text
    }

    $chars = $Text.ToCharArray()
    if ($chars.Count -le 1) {
        return "$(script:New-FlowGraphAnsiColor -Color $startRgb)$Text`e[0m"
    }

    $sb = [System.Text.StringBuilder]::new()
    for ($i = 0; $i -lt $chars.Count; $i++) {
        $t = if ($chars.Count -gt 1) { $i / ($chars.Count - 1) } else { 0 }
        $rgb = script:Blend-FlowGraphRgb -Start $startRgb -End $endRgb -T $t
        [void]$sb.Append((script:New-FlowGraphAnsiColor -Color $rgb))
        [void]$sb.Append($chars[$i])
    }
    [void]$sb.Append("`e[0m")
    return $sb.ToString()
}

function script:Format-FlowGraphNodeText {
    param([hashtable]$Node)

    $label = $Node.Label ?? $Node.Id
    $meta  = if ($Node.Meta) { " [$($Node.Meta)]" } else { '' }
    $text  = " $label$meta "
    $style = $Node.Style

    if ($style -is [hashtable]) {
        $status = if ($null -ne $style.Status) { [string]$style.Status } else { $null }
        $completeStatus = if ($null -ne $style.CompleteStatus) { [string]$style.CompleteStatus } else { $null }
        $colorMode = if ($style.ColorMode) { [string]$style.ColorMode } else { 'Static' }

        if ($completeStatus -and $status -and ($status -ieq $completeStatus) -and $style.CompleteColor) {
            return "$(script:New-FlowGraphAnsiColor -Color $style.CompleteColor)$text`e[0m"
        }

        if ($colorMode -ieq 'Gradient' -and $style.GradientFrom -and $style.GradientTo) {
            if ($style.Value -ne $null) {
                $max = if ($style.Maximum -and [int]$style.Maximum -gt 0) { [int]$style.Maximum } else { 100 }
                $ratio = [Math]::Min(1.0, [Math]::Max(0.0, [double]$style.Value / $max))
                $rgb = script:Blend-FlowGraphRgb -Start $style.GradientFrom -End $style.GradientTo -T $ratio
                return "$(script:New-FlowGraphAnsiColor -Color $rgb)$text`e[0m"
            }

            return script:Format-FlowGraphGradientText -Text $text -Start $style.GradientFrom -End $style.GradientTo
        }

        if ($style.Color) {
            return "$(script:New-FlowGraphAnsiColor -Color $style.Color)$text`e[0m"
        }
    }

    return $text
}

#endregion

#region ─── Node Box Rendering ───────────────────────────────────────────────

function script:Render-NodeBox {
    param(
        [hashtable]$Node,
        [string]$BoxStyle = 'Rounded',
        [bool]$UseColor = $true
    )

    $ui    = $script:FlowGraphUiActive ?? $script:FlowGraphUi
    $style = $ui.BoxStyles[$BoxStyle]
    $label = $Node.Label ?? $Node.Id
    $type  = $Node.Type ?? 'Default'
    $meta  = if ($Node.Meta) { " [$($Node.Meta)]" } else { '' }
    $plain = " $label$meta "
    $inner = if ($UseColor) { script:Format-FlowGraphNodeText -Node $Node } else { $plain }
    $width = script:Get-FlowGraphVisibleLength -Text $plain

    $color  = if ($UseColor) { $ui.NodeTypeColors[$type] ?? $ui.NodeTypeColors['Default'] } else { '' }
    $reset  = if ($UseColor) { $ui.Title.Reset ?? "`e[0m" } else { '' }

    $top    = "$($style.TL)$($style.H * $width)$($style.TR)"
    $middle = "$($style.V)$inner$($style.V)"
    $bottom = "$($style.BL)$($style.H * $width)$($style.BR)"

    return @{
        Top        = "$color$top$reset"
        Middle     = "$color$middle$reset"
        Bottom     = "$color$bottom$reset"
        Width      = $width + 2  # include borders
        InnerWidth = $width
    }
}

#endregion

#region ─── Graph Topology ───────────────────────────────────────────────────

function script:Build-Adjacency {
    param([array]$Edges)

    $adj     = @{}  # parent → [children]
    $parents = @{}  # child → [parents]

    foreach ($e in $Edges) {
        if (-not $adj[$e.From])     { $adj[$e.From]     = [System.Collections.Generic.List[string]]::new() }
        if (-not $parents[$e.To])   { $parents[$e.To]   = [System.Collections.Generic.List[string]]::new() }
        if (-not $adj[$e.To])       { $adj[$e.To]       = [System.Collections.Generic.List[string]]::new() }
        if (-not $parents[$e.From]) { $parents[$e.From] = [System.Collections.Generic.List[string]]::new() }

        $adj[$e.From].Add($e.To)
        $parents[$e.To].Add($e.From)
    }

    return @{ Children = $adj; Parents = $parents }
}

function script:Get-TopologicalOrder {
    param(
        [array]$Nodes,
        [hashtable]$Adjacency
    )

    $inDegree = @{}
    foreach ($n in $Nodes) { $inDegree[$n.Id] = 0 }

    foreach ($n in $Nodes) {
        foreach ($child in $Adjacency.Children[$n.Id]) {
            $inDegree[$child]++
        }
    }

    $queue  = [System.Collections.Queue]::new()
    $sorted = [System.Collections.Generic.List[string]]::new()

    foreach ($n in $Nodes) {
        if ($inDegree[$n.Id] -eq 0) { $queue.Enqueue($n.Id) }
    }

    while ($queue.Count -gt 0) {
        $current = $queue.Dequeue()
        $sorted.Add($current)
        foreach ($child in $Adjacency.Children[$current]) {
            $inDegree[$child]--
            if ($inDegree[$child] -eq 0) { $queue.Enqueue($child) }
        }
    }

    return $sorted.ToArray()
}

function script:Assign-Levels {
    param(
        [array]$Nodes,
        [hashtable]$Adjacency
    )

    $levels  = @{}
    $nodeMap = @{}
    foreach ($n in $Nodes) { $nodeMap[$n.Id] = $n; $levels[$n.Id] = 0 }

    # BFS from roots (nodes with no parents)
    $roots = $Nodes | Where-Object { @($Adjacency.Parents[$_.Id]).Count -eq 0 }
    $queue = [System.Collections.Queue]::new()
    foreach ($r in $roots) { $queue.Enqueue($r.Id) }

    while ($queue.Count -gt 0) {
        $current = $queue.Dequeue()
        foreach ($child in $Adjacency.Children[$current]) {
            $newLevel = $levels[$current] + 1
            if ($newLevel -gt $levels[$child]) {
                $levels[$child] = $newLevel
                $queue.Enqueue($child)
            }
        }
    }

    # Group nodes by level
    $byLevel = @{}
    foreach ($n in $Nodes) {
        $l = $levels[$n.Id]
        if (-not $byLevel[$l]) { $byLevel[$l] = [System.Collections.Generic.List[object]]::new() }
        $byLevel[$l].Add($n)
    }

    return @{ Levels = $levels; ByLevel = $byLevel; MaxLevel = ($levels.Values | Measure-Object -Maximum).Maximum }
}

#endregion

#region ─── Layout Renderers ─────────────────────────────────────────────────

function script:Render-TopDown {
    param(
        [array]$Nodes,
        [array]$Edges,
        [hashtable]$Options
    )

    $ui         = $script:FlowGraphUiActive ?? $script:FlowGraphUi
    $boxStyle   = $Options.BoxStyle   ?? 'Rounded'
    $connStyle  = $Options.ConnStyle  ?? 'Arrow'
    $useColor   = $Options.UseColor   ?? $true
    $padding    = $Options.Padding    ?? 2
    $colWidth   = $Options.ColWidth   ?? 0   # 0 = auto

    $adj        = script:Build-Adjacency -Edges $Edges
    $layout     = script:Assign-Levels   -Nodes $Nodes -Adjacency $adj
    $conn       = $ui.ConnectorStyles[$connStyle]

    $nodeBoxes  = @{}
    foreach ($n in $Nodes) {
        $nodeBoxes[$n.Id] = script:Render-NodeBox -Node $n -BoxStyle $boxStyle -UseColor $useColor
    }

    # Auto column width = widest box at any level
    if ($colWidth -eq 0) {
        $colWidth = ($nodeBoxes.Values | ForEach-Object { $_.Width } | Measure-Object -Maximum).Maximum
    }

    $lines = [System.Collections.Generic.List[string]]::new()
    $reset = if ($useColor) { $ui.Title.Reset ?? "`e[0m" } else { '' }
    $dimC  = if ($useColor) { "`e[90m" } else { '' }  # dim for connectors

    for ($lvl = 0; $lvl -le $layout.MaxLevel; $lvl++) {
        $levelNodes = $layout.ByLevel[$lvl]
        if (-not $levelNodes) { continue }

        $gap     = ' ' * $padding
        $topCells = [System.Collections.Generic.List[hashtable]]::new()
        $midCells = [System.Collections.Generic.List[hashtable]]::new()
        $botCells = [System.Collections.Generic.List[hashtable]]::new()

        foreach ($n in $levelNodes) {
            $box = $nodeBoxes[$n.Id]
            $topCells.Add(@{ Text = $box.Top;    Width = $colWidth; Align = 'Center' })
            $midCells.Add(@{ Text = $box.Middle; Width = $colWidth; Align = 'Center' })
            $botCells.Add(@{ Text = $box.Bottom; Width = $colWidth; Align = 'Center' })
        }

        $lines.Add((Clap -Cells $topCells -Separator $gap))
        $lines.Add((Clap -Cells $midCells -Separator $gap))
        $lines.Add((Clap -Cells $botCells -Separator $gap))

        # Render connectors to next level
        if ($lvl -lt $layout.MaxLevel) {
            $connRow1 = [System.Collections.Generic.List[hashtable]]::new()
            $connRow2 = [System.Collections.Generic.List[hashtable]]::new()
            foreach ($n in $levelNodes) {
                $hasChildren = $adj.Children[$n.Id].Count -gt 0
                if ($hasChildren) {
                    $connRow1.Add(@{ Text = "$dimC$($conn.Line)$reset"; Width = $colWidth; Align = 'Center' })
                    $connRow2.Add(@{ Text = "$dimC$($conn.Down)$reset"; Width = $colWidth; Align = 'Center' })
                } else {
                    $connRow1.Add(@{ Text = ''; Width = $colWidth; Align = 'Center' })
                    $connRow2.Add(@{ Text = ''; Width = $colWidth; Align = 'Center' })
                }
            }

            $lines.Add((Clap -Cells $connRow1 -Separator $gap))
            $lines.Add((Clap -Cells $connRow2 -Separator $gap))
        }
    }

    return $lines
}

function script:Render-LeftRight {
    param(
        [array]$Nodes,
        [array]$Edges,
        [hashtable]$Options
    )

    $ui         = $script:FlowGraphUiActive ?? $script:FlowGraphUi
    $boxStyle   = $Options.BoxStyle  ?? 'Rounded'
    $connStyle  = $Options.ConnStyle ?? 'Arrow'
    $useColor   = $Options.UseColor  ?? $true

    $adj        = script:Build-Adjacency -Edges $Edges
    $layout     = script:Assign-Levels  -Nodes $Nodes -Adjacency $adj
    $conn       = $ui.ConnectorStyles[$connStyle]
    $nodeBoxes  = @{}
    foreach ($n in $Nodes) {
        $nodeBoxes[$n.Id] = script:Render-NodeBox -Node $n -BoxStyle $boxStyle -UseColor $useColor
    }

    $reset = if ($useColor) { $ui.Title.Reset ?? "`e[0m" } else { '' }
    $dimC  = if ($useColor) { "`e[90m" } else { '' }

    # Max nodes in any level = row count
    $maxRows = ($layout.ByLevel.Values | ForEach-Object { $_.Count } | Measure-Object -Maximum).Maximum
    $levelWidths = @{}
    for ($lvl = 0; $lvl -le $layout.MaxLevel; $lvl++) {
        $lvlNodes = $layout.ByLevel[$lvl]
        if ($lvlNodes) {
            $levelWidths[$lvl] = ($lvlNodes | ForEach-Object { $nodeBoxes[$_.Id].Width } | Measure-Object -Maximum).Maximum
        } else {
            $levelWidths[$lvl] = 0
        }
    }

    # Build a 2D grid: [level][row] = nodeId or $null
    $grid = @{}
    for ($lvl = 0; $lvl -le $layout.MaxLevel; $lvl++) {
        $grid[$lvl] = @($null) * $maxRows
        $lvlNodes   = $layout.ByLevel[$lvl]
        if ($lvlNodes) {
            for ($i = 0; $i -lt $lvlNodes.Count; $i++) {
                $grid[$lvl][$i] = $lvlNodes[$i].Id
            }
        }
    }

    $lines    = [System.Collections.Generic.List[string]]::new()
    $nodeMap  = @{}
    foreach ($n in $Nodes) { $nodeMap[$n.Id] = $n }

    for ($row = 0; $row -lt $maxRows; $row++) {
        $rowLines = @(
            [System.Collections.Generic.List[hashtable]]::new(),
            [System.Collections.Generic.List[hashtable]]::new(),
            [System.Collections.Generic.List[hashtable]]::new(),
            [System.Collections.Generic.List[hashtable]]::new()
        )

        for ($lvl = 0; $lvl -le $layout.MaxLevel; $lvl++) {
            $nId = $grid[$lvl][$row]
            $colWidth = $levelWidths[$lvl]

            if ($nId) {
                $box = $nodeBoxes[$nId]
                $rowLines[0].Add(@{ Text = $box.Top;    Width = $colWidth + 2; Align = 'Center' })
                $rowLines[1].Add(@{ Text = $box.Middle; Width = $colWidth + 3; Align = 'Center' })
                $rowLines[2].Add(@{ Text = $box.Bottom; Width = $colWidth + 2; Align = 'Center' })
                $rowLines[3].Add(@{ Text = ''; Width = $colWidth + 2; Align = 'Center' })

                # Add connector arrow if children exist at next level
                if ($lvl -lt $layout.MaxLevel) {
                    $hasEdge = $adj.Children[$nId].Count -gt 0
                    if ($hasEdge) {
                        $rowLines[1][$rowLines[1].Count - 1].Text += " $dimC$($conn.HLine)$($conn.HLine)$($conn.Right)$reset"
                    }
                }
            } else {
                # Empty cell — keep the same column width so the grid stays aligned.
                $rowLines[0].Add(@{ Text = ''; Width = $colWidth + 2; Align = 'Center' })
                $rowLines[1].Add(@{ Text = ''; Width = $colWidth + 3; Align = 'Center' })
                $rowLines[2].Add(@{ Text = ''; Width = $colWidth + 2; Align = 'Center' })
                $rowLines[3].Add(@{ Text = ''; Width = $colWidth + 2; Align = 'Center' })
            }
        }

        foreach ($l in $rowLines) { $lines.Add((Clap -Cells $l)) }
    }

    return $lines
}

function script:Render-Pipeline {
    param(
        [array]$Nodes,
        [array]$Edges,
        [hashtable]$Options
    )

    # Linear left-to-right pipeline — single row, stages connected with arrows
    $ui        = $script:FlowGraphUiActive ?? $script:FlowGraphUi
    $boxStyle  = $Options.BoxStyle  ?? 'Single'
    $connStyle = $Options.ConnStyle ?? 'Arrow'
    $useColor  = $Options.UseColor  ?? $true

    $adj       = script:Build-Adjacency -Edges $Edges
    $topo      = @(script:Get-TopologicalOrder -Nodes $Nodes -Adjacency $adj)
    $conn      = $ui.ConnectorStyles[$connStyle]
    $nodeMap   = @{}
    foreach ($n in $Nodes) { $nodeMap[$n.Id] = $n }

    $reset = if ($useColor) { $ui.Title.Reset ?? "`e[0m" } else { '' }
    $dimC  = if ($useColor) { "`e[90m" } else { '' }

    $topCells = [System.Collections.Generic.List[hashtable]]::new()
    $midCells = [System.Collections.Generic.List[hashtable]]::new()
    $botCells = [System.Collections.Generic.List[hashtable]]::new()

    for ($i = 0; $i -lt $topo.Count; $i++) {
        $nId = $topo[$i]
        $n   = $nodeMap[$nId]
        if (-not $n) { continue }
        $box     = script:Render-NodeBox -Node $n -BoxStyle $boxStyle -UseColor $useColor
        $topCells.Add(@{ Text = $box.Top;    Width = $box.Width; Align = 'Center' })
        $midCells.Add(@{ Text = $box.Middle; Width = $box.Width; Align = 'Center' })
        $botCells.Add(@{ Text = $box.Bottom; Width = $box.Width; Align = 'Center' })

        if ($i -lt $topo.Count - 1) {
            $topCells.Add(@{ Text = ''; Width = 4; Align = 'Center' })
            $midCells.Add(@{ Text = "$dimC $($conn.HLine)$($conn.Right)$reset "; Width = 4; Align = 'Center' })
            $botCells.Add(@{ Text = ''; Width = 4; Align = 'Center' })
        }
    }

    return @(
        (Clap -Cells $topCells)
        (Clap -Cells $midCells)
        (Clap -Cells $botCells)
    )
}

function script:Render-Tree {
    param(
        [array]$Nodes,
        [array]$Edges,
        [hashtable]$Options
    )

    # Classic tree with branch characters — roots at top, branching down
    $ui        = $script:FlowGraphUiActive ?? $script:FlowGraphUi
    $boxStyle  = $Options.BoxStyle  ?? 'Rounded'
    $useColor  = $Options.UseColor  ?? $true
    $indent    = $Options.Indent    ?? 4

    $adj       = script:Build-Adjacency -Edges $Edges
    $nodeMap   = @{}
    foreach ($n in $Nodes) { $nodeMap[$n.Id] = $n }

    $reset = if ($useColor) { $ui.Title.Reset ?? "`e[0m" } else { '' }
    $dimC  = if ($useColor) { "`e[90m" } else { '' }

    $lines = [System.Collections.Generic.List[string]]::new()

    function Recurse-Node {
        param([string]$Id, [string]$Prefix = '', [bool]$IsLast = $true)

        $n       = $nodeMap[$Id]
        $label   = $n.Label ?? $n.Id
        $type    = $n.Type  ?? 'Default'
        $meta    = if ($n.Meta) { " [$($n.Meta)]" } else { '' }
        $color   = if ($useColor) { $ui.NodeTypeColors[$type] ?? $ui.NodeTypeColors['Default'] } else { '' }
        $branch  = if ($IsLast) { '└── ' } else { '├── ' }
        $cont    = if ($IsLast) { '    ' } else { '│   ' }

        $lines.Add("$dimC$Prefix$branch$reset$color$label$meta$reset")

        $children = @($adj.Children[$Id] | Where-Object { $_ })
        for ($i = 0; $i -lt $children.Count; $i++) {
            Recurse-Node -Id $children[$i] -Prefix ($Prefix + $cont) -IsLast ($i -eq $children.Count - 1)
        }
    }

    # Find roots
    $roots = $Nodes | Where-Object { @($adj.Parents[$_.Id]).Count -eq 0 }
    for ($i = 0; $i -lt @($roots).Count; $i++) {
        $r     = @($roots)[$i]
        $label = $r.Label ?? $r.Id
        $type  = $r.Type  ?? 'Default'
        $color = if ($useColor) { $ui.NodeTypeColors[$type] ?? $ui.NodeTypeColors['Default'] } else { '' }
        $lines.Add("$color$label$reset")
        $children = @($adj.Children[$r.Id] | Where-Object { $_ })
        for ($j = 0; $j -lt $children.Count; $j++) {
            Recurse-Node -Id $children[$j] -Prefix '' -IsLast ($j -eq $children.Count - 1)
        }
        if ($i -lt @($roots).Count - 1) { $lines.Add('') }
    }

    return $lines
}

#endregion

#region ─── Legend ────────────────────────────────────────────────────────────

function script:Render-Legend {
    param(
        [array]$Nodes,
        [string]$BoxStyle = 'Rounded',
        [bool]$UseColor   = $true
    )

    $ui    = $script:FlowGraphUiActive ?? $script:FlowGraphUi
    $usedTypes = @($Nodes | ForEach-Object { $_.Type ?? 'Default' } | Sort-Object -Unique)
    if ($usedTypes.Count -le 1 -and $usedTypes[0] -eq 'Default') { return @() }

    $style = $ui.BoxStyles[$BoxStyle]
    $reset = if ($UseColor) { $ui.Title.Reset ?? "`e[0m" } else { '' }
    $dimC  = if ($UseColor) { "`e[90m" } else { '' }

    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add("$dimC── Legend $($style.H * 30)$reset")

    foreach ($t in $usedTypes) {
        $color  = if ($UseColor) { $ui.NodeTypeColors[$t] ?? $ui.NodeTypeColors['Default'] } else { '' }
        $lines.Add("  $color■$reset $t")
    }

    return $lines
}

#endregion
