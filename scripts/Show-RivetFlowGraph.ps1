function Show-RivetFlowGraph {
    <#
    .SYNOPSIS
        Renders a terminal ASCII flow graph of Rivet's release and automation lifecycle.
    .DESCRIPTION
        Utilizes the Flowgraph engine to visualize the stages of Rivet: Git worktree discovery,
        doctor diagnostics, SemVer calculation, manifest synchronization, release documentation,
        merge request management, scoped commit reviews, tag validation, and GitLab publication.
    .PARAMETER Layout
        Graph layout algorithm: TopDown, Pipeline, Tree, or LeftRight. Default: Pipeline (if terminal is wide) or TopDown.
    .PARAMETER BoxStyle
        Box character drawing style: Rounded, Double, Single, Heavy, or Ascii. Default: Rounded.
    .PARAMETER PassThru
        Returns the rendered string array instead of printing directly to console.
    #>
    [CmdletBinding()]
    param(
        [ValidateSet('TopDown', 'Pipeline', 'Tree', 'LeftRight')]
        [string]$Layout,

        [ValidateSet('Rounded', 'Double', 'Single', 'Heavy', 'Ascii')]
        [string]$BoxStyle = 'Rounded',

        [switch]$PassThru
    )

    if (-not (Get-Command New-FlowNode -ErrorAction SilentlyContinue)) {
        $fgRoot = [System.IO.Path]::Combine($PSScriptRoot, 'helpers', 'flowgraph')
        foreach ($file in @(
            [System.IO.Path]::Combine($fgRoot, 'private', 'Engine.ps1'),
            [System.IO.Path]::Combine($fgRoot, 'public', 'New-FlowNode.ps1'),
            [System.IO.Path]::Combine($fgRoot, 'public', 'New-FlowEdge.ps1'),
            [System.IO.Path]::Combine($fgRoot, 'public', 'New-FlowGraph.ps1'),
            [System.IO.Path]::Combine($fgRoot, 'public', 'Show-FlowGraph.ps1')
        )) {
            if ([System.IO.File]::Exists($file)) { . $file }
        }
    }

    $termWidth = try { [Console]::WindowWidth } catch { 0 }
    if ($termWidth -le 0) { $termWidth = 100 }
    if ([string]::IsNullOrWhiteSpace($Layout)) {
        $Layout = if ($termWidth -ge 120) { 'Pipeline' } else { 'TopDown' }
    }

    $nodes = @(
        (New-FlowNode 'git'       'Git Worktree'    Start    -Meta 'context')
        (New-FlowNode 'doctor'    'Doctor Checks'   Decision -Meta 'health')
        (New-FlowNode 'init'      'Init / Scaffold' Process  -Meta 'repository profile')
        (New-FlowNode 'version'   'SemVer Engine'   Process  -Meta 'conventional')
        (New-FlowNode 'manifests' 'Manifest Sync'   IO       -Meta 'package | jsr')
        (New-FlowNode 'docs'      'Release Docs'    Process  -Meta 'changelog | notes')
        (New-FlowNode 'mr'        'Merge Request'   Process  -Meta 'mr.md | IID')
        (New-FlowNode 'commit'    'Scoped Commit'   Process  -Meta 'interactive')
        (New-FlowNode 'tag'       'Tag Validation'  Decision -Meta 'release | snapshot')
        (New-FlowNode 'gitlab'    'GitLab Release'  End      -Meta 'CI / Pages')
    )

    $edges = @(
        (New-FlowEdge 'git'       'doctor')
        (New-FlowEdge 'doctor'    'init')
        (New-FlowEdge 'doctor'    'version')
        (New-FlowEdge 'version'   'manifests')
        (New-FlowEdge 'manifests' 'docs')
        (New-FlowEdge 'docs'      'mr')
        (New-FlowEdge 'mr'        'commit')
        (New-FlowEdge 'commit'    'tag')
        (New-FlowEdge 'tag'       'gitlab')
    )

    $emberUi = @{
        Title = @{
            Accent = "`e[38;2;255;130;0m"
            Bold   = "`e[1m"
        }
        NodeTypeColors = @{
            Default  = "`e[38;2;220;225;235m"
            Start    = "`e[38;2;80;220;150m"
            End      = "`e[38;2;255;90;105m"
            Process  = "`e[38;2;255;140;40m"
            Decision = "`e[38;2;255;195;75m"
            IO       = "`e[38;2;210;120;255m"
            Warning  = "`e[38;2;255;180;0m"
            Info     = "`e[38;2;0;200;255m"
            Success  = "`e[38;2;80;220;150m"
        }
    }

    $graph = New-FlowGraph `
        -Nodes $nodes `
        -Edges $edges `
        -Layout $Layout `
        -BoxStyle $BoxStyle `
        -MaxWidth $(if ($Layout -eq 'Pipeline') { [Math]::Max(20, $termWidth - 2) } else { 0 }) `
        -Title 'RIVET AUTOMATION LIFECYCLE' `
        -Ui $emberUi `
        -ShowLegend $true

    if ($PassThru) {
        return (ConvertTo-FlowGraph -Graph $graph)
    }

    Show-FlowGraph -Graph $graph
}
