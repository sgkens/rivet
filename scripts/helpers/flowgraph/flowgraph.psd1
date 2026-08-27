@{
    ModuleVersion     = '1.0.0'
    GUID              = 'a3f2c1d4-8b7e-4f6a-9c2d-1e5b3a7f0d8c'
    Author            = 'Garvey k. Snow'
    Description       = 'ASCII flow graph renderer for PowerShell. Visualize pipelines, dependency trees, CI/CD stages, and data flows directly in your terminal.'
    PowerShellVersion = '7.0'
    RootModule        = 'flowgraph.psm1'

    FunctionsToExport = @(
        'New-FlowNode'
        'New-FlowEdge'
        'New-FlowGraph'
        'Show-FlowGraph'
        'ConvertTo-FlowGraph'
    )

    PrivateData = @{
        PSData = @{
            Tags       = @('ascii', 'graph', 'visualization', 'pipeline', 'dependency', 'flowchart', 'terminal')
            ProjectUri = 'https://github.com/phellams/flowgraph'
        }
    }
}
