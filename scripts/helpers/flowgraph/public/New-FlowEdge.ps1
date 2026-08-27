function New-FlowEdge {
    <#
    .SYNOPSIS
        Creates a directed edge between two nodes in a Flowgraph.

    .DESCRIPTION
        Defines a relationship between two nodes. The direction is From → To,
        which can represent: depends-on, requires, parent-child, triggers, outputs-to, etc.

        Aliases for the edge relationship are supported via -Requires, -DependsOn,
        and -Parent to make graph definitions read naturally.

    .PARAMETER From
        The source node Id (the node that leads to, or is the parent of, the target).

    .PARAMETER To
        The target node Id (the node that follows, or is the child of, the source).

    .PARAMETER Label
        Optional label displayed on the connector between nodes (not all layouts support this).

    .EXAMPLE
        New-FlowEdge -From 'build' -To 'test'

    .EXAMPLE
        # Read as: 'deploy' requires 'test'
        New-FlowEdge 'test' 'deploy'

    .EXAMPLE
        New-FlowEdge -From 'api' -To 'db' -Label 'queries'

    .OUTPUTS
        [hashtable] Edge definition hashtable.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$From,

        [Parameter(Mandatory, Position = 1)]
        [ValidateNotNullOrEmpty()]
        [string]$To,

        [Parameter()]
        [string]$Label
    )

    $edge = @{
        From  = $From
        To    = $To
        Label = if ($Label) { $Label } else { $null }
    }
    return $edge
}

# Semantic aliases — let the user express intent naturally
function New-FlowDependency {
    <#
    .SYNOPSIS
        Alias for New-FlowEdge. Reads as: Target depends on Source.
    .EXAMPLE
        New-FlowDependency -Source 'database' -Target 'api'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$Target,
        [string]$Label
    )
    New-FlowEdge -From $Source -To $Target -Label $Label
}

function New-FlowRelation {
    <#
    .SYNOPSIS
        Alias for New-FlowEdge. Reads as: Parent → Child.
    .EXAMPLE
        New-FlowRelation -Parent 'app' -Child 'module-a'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Parent,
        [Parameter(Mandatory)][string]$Child,
        [string]$Label
    )
    New-FlowEdge -From $Parent -To $Child -Label $Label
}
