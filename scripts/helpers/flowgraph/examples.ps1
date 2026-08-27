#!/usr/bin/env pwsh
# Flowgraph showcase
# Run: pwsh -File examples.ps1

Import-Module "$PSScriptRoot/flowgraph.psd1" -Force

function Show-Section {
    param([Parameter(Mandatory)][string]$Title)

    Write-Host ''
    Write-Host ('=' * 92)
    Write-Host $Title
    Write-Host ('=' * 92)
}

function Show-GraphDemo {
    param(
        [Parameter(Mandatory)][string]$Title,
        [Parameter(Mandatory)][array]$Nodes,
        [array]$Edges = @(),
        [ValidateSet('TopDown','LeftRight','Tree','Pipeline')][string]$Layout = 'TopDown',
        [ValidateSet('Single','Double','Rounded','Heavy','Ascii')][string]$BoxStyle = 'Rounded',
        [ValidateSet('Arrow','ArrowThin','Dot','Ascii')][string]$ConnStyle = 'Arrow',
        [bool]$UseColor = $true,
        [bool]$ShowLegend = $true,
        [hashtable]$Ui
    )

    $params = @{
        Nodes      = $Nodes
        Edges      = $Edges
        Layout     = $Layout
        BoxStyle   = $BoxStyle
        ConnStyle  = $ConnStyle
        UseColor   = $UseColor
        ShowLegend = $ShowLegend
        Title      = $Title
    }

    if ($Ui) {
        $params.Ui = $Ui
    }

    New-FlowGraph @params | Show-FlowGraph
    Write-Host ''
}

function New-ThemeUi {
    param(
        [string]$Accent,
        [hashtable]$NodeColors,
        [string]$Bold = "`e[1m"
    )

    return @{
        Title = @{
            Accent = $Accent
            Bold   = $Bold
        }
        NodeTypeColors = $NodeColors
    }
}

$pipelineNodes = @(
    New-FlowNode 'checkout' 'Checkout' Start
    New-FlowNode 'build'    'Build'    Process -Meta '~45s'
    New-FlowNode 'test'     'Test'     Process -Meta '~2m'
    New-FlowNode 'scan'     'Security Scan' Warning -Meta 'SAST'
    New-FlowNode 'package'  'Package'  Process
    New-FlowNode 'deploy'   'Deploy'   End -Meta 'prod'
)

$pipelineEdges = @(
    New-FlowEdge 'checkout' 'build'
    New-FlowEdge 'build'    'test'
    New-FlowEdge 'test'     'scan'
    New-FlowEdge 'scan'     'package'
    New-FlowEdge 'package'  'deploy'
)

$dependencyNodes = @(
    New-FlowNode 'app'    'MyApp'        Start
    New-FlowNode 'api'    'API Layer'    Process
    New-FlowNode 'ui'     'UI Layer'     Process
    New-FlowNode 'db'     'Database'     IO -Meta 'postgres'
    New-FlowNode 'cache'  'Cache'        IO -Meta 'redis'
    New-FlowNode 'auth'   'Auth Service' Info
    New-FlowNode 'logger' 'Logger'       Default
)

$dependencyEdges = @(
    New-FlowEdge 'app'  'api'
    New-FlowEdge 'app'  'ui'
    New-FlowEdge 'api'  'db'
    New-FlowEdge 'api'  'cache'
    New-FlowEdge 'api'  'auth'
    New-FlowEdge 'ui'   'auth'
    New-FlowEdge 'app'  'logger'
)

$moduleNodes = @(
    New-FlowNode 'core'    'Core'       Start
    New-FlowNode 'net'     'Networking' Process
    New-FlowNode 'store'   'Storage'    Process
    New-FlowNode 'auth2'   'Auth'       Process
    New-FlowNode 'api2'    'API'        Process
    New-FlowNode 'cli'     'CLI'        End
    New-FlowNode 'web'     'Web UI'     End
)

$moduleEdges = @(
    New-FlowEdge 'core'  'net'
    New-FlowEdge 'core'  'store'
    New-FlowEdge 'core'  'auth2'
    New-FlowEdge 'net'   'api2'
    New-FlowEdge 'store' 'api2'
    New-FlowEdge 'auth2' 'api2'
    New-FlowEdge 'api2'  'cli'
    New-FlowEdge 'api2'  'web'
)

$dataNodes = @(
    New-FlowNode 'ingest'   'Ingest'   Start -Meta 'kafka'
    New-FlowNode 'parse'    'Parse'    Process
    New-FlowNode 'validate' 'Validate' Decision
    New-FlowNode 'enrich'   'Enrich'   Process
    New-FlowNode 'dlq'      'DLQ'      Error -Meta 'dead letter'
    New-FlowNode 'sink'     'Sink'     End -Meta 'S3'
)

$dataEdges = @(
    New-FlowEdge 'ingest'   'parse'
    New-FlowEdge 'parse'    'validate'
    New-FlowEdge 'validate' 'enrich'
    New-FlowEdge 'validate' 'dlq'
    New-FlowEdge 'enrich'   'sink'
)

$paletteNodes = @(
    New-FlowNode 'default'  'Default'  Default
    New-FlowNode 'start'    'Start'    Start
    New-FlowNode 'process'  'Process'  Process
    New-FlowNode 'decision' 'Decision' Decision
    New-FlowNode 'io'       'IO'       IO
    New-FlowNode 'error'    'Error'    Error
    New-FlowNode 'warning'  'Warning'  Warning
    New-FlowNode 'info'     'Info'     Info
    New-FlowNode 'success'  'Success'  Success
)

$paletteEdges = @(
    New-FlowEdge 'default'  'start'
    New-FlowEdge 'start'    'process'
    New-FlowEdge 'process'  'decision'
    New-FlowEdge 'decision' 'io'
    New-FlowEdge 'io'       'error'
    New-FlowEdge 'error'    'warning'
    New-FlowEdge 'warning'  'info'
    New-FlowEdge 'info'     'success'
)

$styleNodes = @(
    New-FlowNode 'phase-a' 'Warmup' Process -Style @{
        ColorMode    = 'Gradient'
        GradientFrom = @(0, 128, 255)
        GradientTo   = @(255, 0, 160)
        Value        = 15
        Maximum      = 100
    }
    New-FlowNode 'phase-b' 'Running' Process -Style @{
        ColorMode    = 'Gradient'
        GradientFrom = @(0, 128, 255)
        GradientTo   = @(255, 0, 160)
        Value        = 55
        Maximum      = 100
    }
    New-FlowNode 'phase-c' 'Complete' Process -Style @{
        Status         = 'done'
        CompleteStatus = 'done'
        CompleteColor  = @(0, 210, 120)
    }
)

$styleEdges = @(
    New-FlowEdge 'phase-a' 'phase-b'
    New-FlowEdge 'phase-b' 'phase-c'
)

$themes = @(
    @{
        Name = 'Default'
        Ui   = $null
    }
    @{
        Name = 'Neon'
        Ui   = New-ThemeUi -Accent "`e[95m" -NodeColors @{
            Default  = "`e[37m"
            Start    = "`e[92m"
            End      = "`e[91m"
            Process  = "`e[96m"
            Decision = "`e[93m"
            IO       = "`e[95m"
            Error    = "`e[31m"
            Warning  = "`e[33m"
            Info     = "`e[94m"
            Success  = "`e[32m"
        }
    }
    @{
        Name = 'Aurora'
        Ui   = New-ThemeUi -Accent "`e[96m" -NodeColors @{
            Default  = "`e[37m"
            Start    = "`e[92m"
            End      = "`e[91m"
            Process  = "`e[38;2;0;200;255m"
            Decision = "`e[38;2;255;220;80m"
            IO       = "`e[38;2;205;125;255m"
            Error    = "`e[38;2;255;90;90m"
            Warning  = "`e[38;2;255;180;0m"
            Info     = "`e[38;2;80;160;255m"
            Success  = "`e[38;2;60;220;140m"
        }
    }
    @{
        Name = 'Ember'
        Ui   = New-ThemeUi -Accent "`e[38;2;255;140;70m" -NodeColors @{
            Default  = "`e[37m"
            Start    = "`e[38;2;255;190;120m"
            End      = "`e[38;2;255;80;80m"
            Process  = "`e[38;2;255;170;0m"
            Decision = "`e[38;2;255;210;80m"
            IO       = "`e[38;2;255;120;40m"
            Error    = "`e[38;2;255;60;40m"
            Warning  = "`e[38;2;255;190;60m"
            Info     = "`e[38;2;255;210;150m"
            Success  = "`e[38;2;255;160;90m"
        }
    }
    @{
        Name = 'Mono'
        Ui   = New-ThemeUi -Accent "`e[97m" -NodeColors @{
            Default  = "`e[97m"
            Start    = "`e[97m"
            End      = "`e[97m"
            Process  = "`e[37m"
            Decision = "`e[90m"
            IO       = "`e[97m"
            Error    = "`e[97m"
            Warning  = "`e[90m"
            Info     = "`e[37m"
            Success  = "`e[97m"
        } -Bold "`e[1m"
    }
)

Show-Section '1. Layout gallery'
Show-GraphDemo -Title 'CI/CD Pipeline' -Nodes $pipelineNodes -Edges $pipelineEdges -Layout Pipeline -BoxStyle Single
Show-GraphDemo -Title 'Application Architecture' -Nodes $dependencyNodes -Edges $dependencyEdges -Layout Tree -BoxStyle Double
Show-GraphDemo -Title 'Module Dependencies' -Nodes $moduleNodes -Edges $moduleEdges -Layout TopDown -BoxStyle Heavy -ConnStyle ArrowThin
Show-GraphDemo -Title 'Data Pipeline' -Nodes $dataNodes -Edges $dataEdges -Layout LeftRight -BoxStyle Rounded -ConnStyle Dot

Show-Section '2. Box style matrix'
foreach ($boxStyle in 'Single', 'Double', 'Rounded', 'Heavy', 'Ascii') {
    Show-GraphDemo -Title "Box style: $boxStyle" -Nodes $pipelineNodes -Edges $pipelineEdges -Layout Pipeline -BoxStyle $boxStyle -ConnStyle Arrow -ShowLegend:$false
}

Show-Section '3. Connector style matrix'
foreach ($connStyle in 'Arrow', 'ArrowThin', 'Dot', 'Ascii') {
    Show-GraphDemo -Title "Connector style: $connStyle" -Nodes $dependencyNodes -Edges $dependencyEdges -Layout TopDown -BoxStyle Rounded -ConnStyle $connStyle
}

Show-Section '4. Theme gallery'
foreach ($theme in $themes) {
    Show-GraphDemo -Title "Theme: $($theme.Name)" -Nodes $paletteNodes -Edges $paletteEdges -Layout Tree -BoxStyle Rounded -ConnStyle Arrow -Ui $theme.Ui
}

Show-Section '5. Node palette'
Show-GraphDemo -Title 'All node types' -Nodes $paletteNodes -Edges $paletteEdges -Layout TopDown -BoxStyle Rounded -ConnStyle Arrow

Show-Section '6. Advanced node styling'
Show-GraphDemo -Title 'Gradient and completion states' -Nodes $styleNodes -Edges $styleEdges -Layout Pipeline -BoxStyle Double -ConnStyle Arrow

Show-Section '7. Plain ASCII export'
$asciiNodes = @(
    New-FlowNode 'a' 'Source'
    New-FlowNode 'b' 'Transform'
    New-FlowNode 'c' 'Destination'
)
$asciiEdges = @(
    New-FlowEdge 'a' 'b'
    New-FlowEdge 'b' 'c'
)

$plain = New-FlowGraph -Nodes $asciiNodes -Edges $asciiEdges -Layout Pipeline -BoxStyle Ascii -ConnStyle Ascii -UseColor:$false -Title 'Plain ASCII' | ConvertTo-FlowGraph
$plainPath = Join-Path ([System.IO.Path]::GetTempPath()) 'flowgraph-plain.txt'
$plain | Out-File -FilePath $plainPath -Encoding utf8
$plain | ForEach-Object { Write-Host $_ }
Write-Host ''
Write-Host "Saved plain output to $plainPath"
