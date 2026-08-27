function New-FlowNode {
    <#
    .SYNOPSIS
        Creates a node definition for use in a Flowgraph.

    .DESCRIPTION
        Defines a node (step, stage, service, component) that will appear in the flow graph.
        Nodes are connected via edges created with New-FlowEdge.

    .PARAMETER Id
        Unique identifier for this node. Used to reference it in edges.

    .PARAMETER Label
        Display label shown inside the node box. Defaults to Id if not set.
        Alias: Name.

    .PARAMETER Type
        Visual type of the node. Controls color when UseColor is enabled.
        Valid values: Default, Start, End, Process, Decision, IO, Error, Warning, Info, Success

    .PARAMETER Meta
        Optional short metadata string shown in brackets next to the label.
        Useful for versions, counts, statuses, etc.

    .PARAMETER Style
        Optional hashtable describing advanced rendering for the node. Common
        keys include:
        Color
        ColorMode
        GradientFrom
        GradientTo
        Value
        Maximum
        Status
        CompleteStatus
        CompleteColor

    .EXAMPLE
        New-FlowNode -Id 'build' -Label 'Build' -Type Process

    .EXAMPLE
        New-FlowNode -Id 'deploy' -Label 'Deploy to Prod' -Type End -Meta 'v2.1.0'

    .OUTPUTS
        [hashtable] Node definition hashtable.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$Id,

        [Parameter(Position = 1)]
        [Alias('Name')]
        [string]$Label,

        [Parameter(Position = 2)]
        [ValidateSet('Default','Start','End','Process','Decision','IO','Error','Warning','Info','Success')]
        [string]$Type = 'Default',

        [Parameter()]
        [string]$Meta,

        [Parameter()]
        [hashtable]$Style
    )

    $node = @{
        Id    = $Id
        Label = if ($Label) { $Label } else { $Id }
        Type  = $Type
        Meta  = if ($Meta) { $Meta } else { $null }
        Style = if ($Style) { $Style } else { $null }
    }

    return $node
}
