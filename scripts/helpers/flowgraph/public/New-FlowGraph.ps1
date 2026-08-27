function New-FlowGraph {
    <#
    .SYNOPSIS
        Creates a Flowgraph definition from nodes and edges.

    .DESCRIPTION
        Assembles a graph definition object from a collection of nodes and edges,
        along with display options. Pass the result to Show-FlowGraph or
        ConvertTo-FlowGraph to render.

    .PARAMETER Nodes
        Array of node hashtables created with New-FlowNode.

    .PARAMETER Edges
        Array of edge hashtables created with New-FlowEdge (or aliases).

    .PARAMETER Layout
        The layout algorithm to use for rendering.

        TopDown    - Levels flow top-to-bottom. Best for pipelines with branching.
        LeftRight  - Levels flow left-to-right. Best for wide dependency graphs.
        Tree       - Classic tree with branch characters. Best for parent/child hierarchies.
        Pipeline   - Single-row linear flow. Best for sequential CI/CD stages.

    .PARAMETER BoxStyle
        The box drawing character style for nodes.
        Single | Double | Rounded | Heavy | Ascii

    .PARAMETER ConnStyle
        The connector/arrow character style.
        Arrow | ArrowThin | Dot | Ascii

    .PARAMETER Title
        Optional title printed above the graph.

    .PARAMETER UseColor
        Enable ANSI color output. Default: $true.
        Set to $false for plain output or piping to files.

    .PARAMETER ShowLegend
        Print a legend for node types below the graph. Default: $true when multiple types are used.

    .PARAMETER Indent
        Indentation width used by the Tree layout. Default: 4.

    .PARAMETER Ui
        Optional theme object used to override box styles, connector styles,
        node colors, or title accents. This is merged with the module defaults.

    .EXAMPLE
        $nodes = @(
            New-FlowNode 'start'  'Checkout'  Start
            New-FlowNode 'build'  'Build'     Process
            New-FlowNode 'test'   'Test'      Process
            New-FlowNode 'deploy' 'Deploy'    End
        )
        $edges = @(
            New-FlowEdge 'start' 'build'
            New-FlowEdge 'build' 'test'
            New-FlowEdge 'test'  'deploy'
        )
        New-FlowGraph -Nodes $nodes -Edges $edges -Layout Pipeline -Title 'CI/CD'

    .OUTPUTS
        [hashtable] Flowgraph definition. Pipe to Show-FlowGraph or ConvertTo-FlowGraph.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [hashtable[]]$Nodes,

        [Parameter(ValueFromPipelineByPropertyName)]
        [hashtable[]]$Edges = @(),

        [Parameter()]
        [ValidateSet('TopDown','LeftRight','Tree','Pipeline')]
        [string]$Layout = 'TopDown',

        [Parameter()]
        [ValidateSet('Single','Double','Rounded','Heavy','Ascii')]
        [string]$BoxStyle = 'Rounded',

        [Parameter()]
        [ValidateSet('Arrow','ArrowThin','Dot','Ascii')]
        [string]$ConnStyle = 'Arrow',

        [Parameter()]
        [string]$Title,

        [Parameter()]
        [bool]$UseColor = $true,

        [Parameter()]
        [bool]$ShowLegend = $true,

        [Parameter()]
        [int]$Indent = 4,

        [Parameter()]
        [int]$Padding = 3,

        [Parameter()]
        [int]$ColWidth = 0,

        [Parameter()]
        [Alias('Theme')]
        [hashtable]$Ui
    )

    return @{
        Nodes      = $Nodes
        Edges      = $Edges
        Layout     = $Layout
        Title      = $Title
        UseColor   = $UseColor
        ShowLegend = $ShowLegend
        Ui         = $Ui
        Options    = @{
            BoxStyle  = $BoxStyle
            ConnStyle = $ConnStyle
            UseColor  = $UseColor
            Indent    = $Indent
            Padding   = $Padding
            ColWidth  = $ColWidth
        }
    }
}
