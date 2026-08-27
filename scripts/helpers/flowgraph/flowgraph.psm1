#Requires -Version 7.0

# ── Flowgraph ─────────────────────────────────────────────────────────────────
# ASCII flow graph renderer for PowerShell.
# Visualize pipelines, dependency trees, CI/CD stages, and data flows
# directly in your terminal.
# ─────────────────────────────────────────────────────────────────────────────

# Dot-source private engine first (contains layout logic and shared state)
Get-ChildItem -Path "$PSScriptRoot/private" -Filter '*.ps1' -Recurse |
    ForEach-Object { . $_.FullName }

# Dot-source public functions
Get-ChildItem -Path "$PSScriptRoot/public" -Filter '*.ps1' -Recurse |
    ForEach-Object { . $_.FullName }

# Export semantic edge aliases
Export-ModuleMember -Function @(
    'New-FlowNode'
    'New-FlowEdge'
    'New-FlowDependency'
    'New-FlowRelation'
    'New-FlowGraph'
    'Show-FlowGraph'
    'ConvertTo-FlowGraph'
)
