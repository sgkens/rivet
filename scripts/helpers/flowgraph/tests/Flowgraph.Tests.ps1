BeforeAll {
    Import-Module "$PSScriptRoot/../flowgraph.psd1" -Force
}

AfterAll {
    Remove-Module flowgraph -Force -ErrorAction SilentlyContinue
}

Describe 'Flowgraph module' {
    It 'creates a node with default label and optional style payload' {
        $node = New-FlowNode 'build' 'Build' Process -Meta '~45s' -Style @{
            ColorMode    = 'Gradient'
            GradientFrom = @(0, 128, 255)
            GradientTo   = @(255, 0, 128)
            Value        = 40
            Maximum      = 100
        }

        $node.Id | Should -Be 'build'
        $node.Label | Should -Be 'Build'
        $node.Type | Should -Be 'Process'
        $node.Meta | Should -Be '~45s'
        $node.Style.ColorMode | Should -Be 'Gradient'
        $node.Style.Value | Should -Be 40
    }

    It 'builds a graph definition with theme overrides' {
        $graph = New-FlowGraph -Nodes @(
            New-FlowNode 'a' 'Alpha'
        ) -Theme @{
            Title = @{ Accent = "`e[95m" }
        }

        $graph.Nodes.Count | Should -Be 1
        $graph.Options.BoxStyle | Should -Be 'Rounded'
        $graph.Ui.Title.Accent | Should -Be "`e[95m"
    }

    It 'renders a single-node pipeline without throwing' {
        $graph = New-FlowGraph -Nodes @(
            New-FlowNode 'a' 'Alpha' Process
        ) -Layout Pipeline -UseColor:$false -ShowLegend:$false -BoxStyle Single

        $lines = $graph | ConvertTo-FlowGraph
        ($lines -join "`n") | Should -Match 'Alpha'
        ($lines -join "`n") | Should -Match '┌'
        ($lines -join "`n") | Should -Match '┘'
    }

    It 'applies a themed title accent' {
        $graph = New-FlowGraph -Nodes @(
            New-FlowNode 'a' 'Alpha' Process
        ) -Title 'Deploy' -Theme @{
            Title = @{
                Accent = "`e[95m"
                Bold   = "`e[1m"
            }
        }

        $lines = $graph | ConvertTo-FlowGraph
        $lines[0] | Should -Match ([regex]::Escape("`e[95m"))
        ($lines -join "`n") | Should -Match 'Deploy'
    }

    It 'sizes the title bar by visible width rather than ANSI length' {
        $graph = New-FlowGraph -Nodes @(
            New-FlowNode 'a' 'Alpha' Process
        ) -Title "`e[95mDeploy`e[0m" -ShowLegend:$false

        $lines = $graph | ConvertTo-FlowGraph
        ([regex]::Replace($lines[0], '\x1B\[[0-9;]*[a-zA-Z]', '')).Length | Should -Be 12
        ([regex]::Replace($lines[1], '\x1B\[[0-9;]*[a-zA-Z]', '')).Length | Should -Be 12
        ([regex]::Replace($lines[2], '\x1B\[[0-9;]*[a-zA-Z]', '')).Length | Should -Be 12
    }

    It 'keeps pipeline rows aligned at the same visible width' {
        $graph = New-FlowGraph -Nodes @(
            New-FlowNode 'a' 'Short' Process -Style @{
                Color = @(0, 200, 255)
            }
            New-FlowNode 'b' 'A much longer label' End
        ) -Edges @(
            New-FlowEdge 'a' 'b'
        ) -Layout Pipeline -ShowLegend:$false

        $lines = $graph | ConvertTo-FlowGraph
        $body = $lines | Select-Object -Last 3
        $widths = @($body | ForEach-Object { ([regex]::Replace($_, '\x1B\[[0-9;]*[a-zA-Z]', '')).Length })
        $widths[0] | Should -Be $widths[1]
        $widths[1] | Should -Be $widths[2]
    }

    It 'supports gradient node styling' {
        $graph = New-FlowGraph -Nodes @(
            New-FlowNode 'a' 'Alpha' Process -Style @{
                ColorMode    = 'Gradient'
                GradientFrom = @(0, 128, 255)
                GradientTo   = @(255, 0, 128)
            }
        ) -Layout Pipeline

        $lines = $graph | ConvertTo-FlowGraph
        ($lines -join "`n") | Should -Match ([regex]::Escape("`e[38;2;"))
    }
}
