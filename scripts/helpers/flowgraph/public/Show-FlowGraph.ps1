function ConvertTo-FlowGraph {
    <#
    .SYNOPSIS
        Renders a Flowgraph definition to an array of strings.

    .DESCRIPTION
        Takes a graph definition (from New-FlowGraph) and returns the rendered
        ASCII graph as an array of strings. Use this to capture output, write to
        files, or embed in other output.

    .PARAMETER Graph
        A Flowgraph definition hashtable from New-FlowGraph.

    .EXAMPLE
        $graph = New-FlowGraph -Nodes $nodes -Edges $edges -Layout Tree
        $lines = $graph | ConvertTo-FlowGraph
        $lines | Out-File 'graph.txt'

    .OUTPUTS
        [string[]] Rendered ASCII graph lines.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [hashtable]$Graph
    )

    $nodes   = $Graph.Nodes
    $edges   = $Graph.Edges   ?? @()
    $layout  = $Graph.Layout  ?? 'TopDown'
    $opts    = $Graph.Options
    $title   = $Graph.Title
    $legend  = $Graph.ShowLegend ?? $true
    $color   = $opts.UseColor    ?? $true
    $ui      = script:Resolve-FlowGraphUi -Overrides $Graph.Ui
    $script:FlowGraphUiActive = $ui
    $opts['Ui'] = $ui

    $reset   = if ($color) { $ui.Title.Reset ?? "`e[0m" } else { '' }
    $dimC    = if ($color) { "`e[90m" } else { '' }
    $bold    = if ($color) { $ui.Title.Bold ?? "`e[1m" } else { '' }
    $accent  = if ($color) { $ui.Title.Accent ?? "`e[96m" } else { '' }

    $output  = [System.Collections.Generic.List[string]]::new()

    # ── Header ───────────────────────────────────────────────────────────────
    if ($title) {
        $titleWidth = script:Get-FlowGraphVisibleLength -Text $title
        $bar = '─' * ($titleWidth + 4)
        $titleLine = Clap -Cells @(
            @{
                Text    = "$bold$title$reset"
                Width   = $titleWidth + 4
                Align   = 'Center'
                PadChar = ' '
            }
        )
        $output.Add("$accent╭$bar╮$reset")
        $output.Add("$accent│$titleLine│$reset")
        $output.Add("$accent╰$bar╯$reset")
        $output.Add('')
    }

    # ── Layout render ─────────────────────────────────────────────────────────
    $rendered = switch ($layout) {
        'TopDown'   { script:Render-TopDown   -Nodes $nodes -Edges $edges -Options $opts }
        'LeftRight' { script:Render-LeftRight -Nodes $nodes -Edges $edges -Options $opts }
        'Pipeline'  { script:Render-Pipeline  -Nodes $nodes -Edges $edges -Options $opts }
        'Tree'      { script:Render-Tree      -Nodes $nodes -Edges $edges -Options $opts }
        default     { script:Render-TopDown   -Nodes $nodes -Edges $edges -Options $opts }
    }

    foreach ($line in $rendered) { $output.Add($line) }

    # ── Legend ────────────────────────────────────────────────────────────────
    if ($legend) {
        $legendLines = script:Render-Legend -Nodes $nodes -BoxStyle ($opts.BoxStyle ?? 'Rounded') -UseColor $color
        if ($legendLines.Count -gt 0) {
            $output.Add('')
            foreach ($l in $legendLines) { $output.Add($l) }
        }
    }

    return $output.ToArray()
}

function Show-FlowGraph {
    <#
    .SYNOPSIS
        Renders and prints a Flowgraph to the terminal.

    .DESCRIPTION
        Takes a graph definition (from New-FlowGraph) and writes the ASCII graph
        directly to the terminal via Write-Host. For capturing output as strings,
        use ConvertTo-FlowGraph instead.

    .PARAMETER Graph
        A Flowgraph definition hashtable from New-FlowGraph.

    .PARAMETER PassThru
        If set, also returns the rendered lines as strings in addition to printing.

    .EXAMPLE
        New-FlowGraph -Nodes $nodes -Edges $edges -Layout TopDown | Show-FlowGraph

    .EXAMPLE
        $graph = New-FlowGraph -Nodes $nodes -Edges $edges -Title 'Deploy Pipeline'
        Show-FlowGraph -Graph $graph

    .OUTPUTS
        None (or [string[]] if -PassThru is used)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [hashtable]$Graph,

        [Parameter()]
        [switch]$PassThru
    )

    $lines = ConvertTo-FlowGraph -Graph $Graph
    foreach ($line in $lines) { Write-Host $line }

    if ($PassThru) { return $lines }
}
