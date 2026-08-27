# Flowgraph

> ASCII flow graph renderer for PowerShell. Visualize pipelines, dependency trees, CI/CD stages, and data flows directly in your terminal.

---

## Install

```powershell
# Clone or copy the module folder into your PSModulePath
Import-Module ./Flowgraph/Flowgraph.psd1
```

---

## Quick Start

```powershell
$nodes = @(
    New-FlowNode 'checkout' 'Checkout' Start
    New-FlowNode 'build'    'Build'    Process
    New-FlowNode 'test'     'Test'     Process
    New-FlowNode 'deploy'   'Deploy'   End
)

$edges = @(
    New-FlowEdge 'checkout' 'build'
    New-FlowEdge 'build'    'test'
    New-FlowEdge 'test'     'deploy'
)

New-FlowGraph -Nodes $nodes -Edges $edges -Layout Pipeline -Title 'Deploy' |
    Show-FlowGraph
```

Output:

```
╭────────────╮
│  Deploy    │
╰────────────╯

+----------+ →  +---------+ →  +--------+ →  +---------+
| Checkout |    |  Build  |    |  Test  |    | Deploy  |
+----------+    +---------+    +--------+    +---------+
```

---

## Concepts

**Nodes** are the boxes — steps, services, stages, modules, or any labelled entity.  
**Edges** are the arrows — directed relationships between nodes.  
**Layouts** are the rendering algorithm — how nodes are arranged spatially.

---

## Functions

### `New-FlowNode`

```powershell
New-FlowNode [-Id] <string> [[-Label] <string>] [-Type <string>] [-Meta <string>] [-Style <hashtable>]
```

| Parameter | Description |
|-----------|-------------|
| `Id`      | Unique identifier (used in edges) |
| `Label`   | Display text inside the box. Defaults to `Id`. |
| `Type`    | Visual color type (see Node Types below) |
| `Meta`    | Short metadata shown in `[brackets]` after the label |
| `Style`   | Optional rendering payload for gradients, static colors, and status-driven color changes |

`Style` supports the following keys:

| Key | Purpose |
|-----|---------|
| `Color` | Static RGB color for the node label and border |
| `ColorMode` | `Static` or `Gradient` |
| `GradientFrom` / `GradientTo` | RGB arrays or hex strings used for gradient interpolation |
| `Value` / `Maximum` | Progress-style interpolation, useful in loops and animations |
| `Status` / `CompleteStatus` | Switch to a completion color when a node reaches a terminal state |
| `CompleteColor` | Static RGB color used when `Status` matches `CompleteStatus` |

---

### `New-FlowEdge`

```powershell
New-FlowEdge [-From] <string> [-To] <string> [-Label <string>]
```

Defines a directed relationship: `From → To`.

**Semantic aliases** — same function, expressive naming:

```powershell
# Read as: 'database' is depended on by 'api'
New-FlowDependency -Source 'database' -Target 'api'

# Read as: 'app' is parent of 'module-a'
New-FlowRelation -Parent 'app' -Child 'module-a'
```

---

### `New-FlowGraph`

```powershell
New-FlowGraph -Nodes <hashtable[]> [-Edges <hashtable[]>]
              [-Layout <string>] [-BoxStyle <string>] [-ConnStyle <string>]
              [-Title <string>] [-UseColor <bool>] [-ShowLegend <bool>]
              [-Padding <int>] [-ColWidth <int>] [-Indent <int>] [-Ui <hashtable>]
```

| Parameter    | Values                              | Default    |
|--------------|-------------------------------------|------------|
| `Layout`     | `TopDown` `LeftRight` `Tree` `Pipeline` | `TopDown` |
| `BoxStyle`   | `Rounded` `Single` `Double` `Heavy` `Ascii` | `Rounded` |
| `ConnStyle`  | `Arrow` `ArrowThin` `Dot` `Ascii`   | `Arrow`    |
| `UseColor`   | `$true` / `$false`                  | `$true`    |
| `ShowLegend` | `$true` / `$false`                  | `$true`    |
| `Padding`    | Column gap in spaces                | `3`        |
| `ColWidth`   | Fixed column width (`0` = auto)     | `0`        |
| `Indent`     | Tree layout indent width            | `4`        |
| `Ui`         | Theme override object               | default UI |

`Ui` is merged with the module defaults. Use it to swap box sets, connector glyphs,
node type colors, or title accents without changing the renderer logic.

---

### `Show-FlowGraph`

Renders and prints directly to terminal.

```powershell
$graph | Show-FlowGraph
Show-FlowGraph -Graph $graph -PassThru   # also returns string[]
```

---

### `ConvertTo-FlowGraph`

Returns rendered lines as `[string[]]` — for capture, file output, or embedding.

```powershell
$lines = $graph | ConvertTo-FlowGraph
$lines | Out-File 'diagram.txt' -Encoding utf8
```

---

## Layouts

### `Pipeline` — Linear horizontal flow
Best for sequential CI/CD stages or ordered steps.
```
╭─────────╮    ╭────────╮    ╭──────╮    ╭────────╮
│ Checkout│ ─▶ │ Build  │ ─▶ │ Test │ ─▶ │ Deploy │
╰─────────╯    ╰────────╯    ╰──────╯    ╰────────╯
```

### `TopDown` — Leveled vertical flow
Best for pipelines with branching, multi-stage DAGs.
```
   ╭──────╮
   │ Core │
   ╰──────╯
      │
      ▼
 ╭────────╮  ╭─────────╮
 │ Net    │  │ Storage │
 ╰────────╯  ╰─────────╯
```

### `Tree` — Branch-character hierarchy
Best for parent/child relationships, module trees, org charts.
```
MyApp
├── API Layer
│   ├── Database [postgres]
│   └── Cache [redis]
└── UI Layer
    └── Auth Service
```

### `LeftRight` — Horizontal level grid
Best for wide dependency graphs that read left-to-right.

---

## Node Types & Colors

| Type       | Color         | Use for                        |
|------------|---------------|--------------------------------|
| `Default`  | White         | Generic nodes                  |
| `Start`    | Bright green  | Entry points, triggers         |
| `End`      | Bright red    | Terminals, outputs             |
| `Process`  | Bright cyan   | Processing steps               |
| `Decision` | Bright yellow | Conditionals, branch points    |
| `IO`       | Bright magenta| Databases, queues, storage     |
| `Error`    | Red           | Failure paths, dead letters    |
| `Warning`  | Yellow        | Caution nodes                  |
| `Info`     | Blue          | Informational / passive nodes  |
| `Success`  | Green         | Confirmed success paths        |

---

## Themes and animation

Flowgraph now keeps its visual pieces in a script-level UI object so you can theme the module
without rewriting the renderers. A theme can override:

* `BoxStyles`
* `ConnectorStyles`
* `NodeTypeColors`
* `Title`

Example:

```powershell
$graph = New-FlowGraph -Nodes $nodes -Edges $edges -Title 'Deploy' -Theme @{
    Title = @{
        Accent = "`e[95m"
        Bold   = "`e[1m"
    }
    NodeTypeColors = @{
        Process = "`e[36m"
    }
}
```

For animated loops, use `-Style` on nodes to switch colors quickly:

```powershell
$node = New-FlowNode 'job' 'Working' Process -Style @{
    ColorMode    = 'Gradient'
    GradientFrom = @(0, 128, 255)
    GradientTo   = @(255, 0, 128)
    Value        = $progress
    Maximum      = 100
}
```

If `Status` reaches `CompleteStatus`, the renderer uses `CompleteColor` instead. This is useful
for progress-style status updates where you want a static completion color after the animation ends.

For tear-free redraws, the `private/helpers/clap.ps1` helpers keep ANSI strings aligned by visible
width. Use `ConvertTo-FlowGraph` to get a string array and write the whole frame in one shot.

---

## Examples

### Microservice dependency graph

```powershell
$nodes = @(
    New-FlowNode 'gateway'  'API Gateway'   Start
    New-FlowNode 'auth'     'Auth'          Process
    New-FlowNode 'orders'   'Orders'        Process
    New-FlowNode 'payments' 'Payments'      Process
    New-FlowNode 'db'       'PostgreSQL'    IO      -Meta 'primary'
    New-FlowNode 'queue'    'RabbitMQ'      IO
    New-FlowNode 'notify'   'Notify'        End
)

$edges = @(
    New-FlowEdge 'gateway'  'auth'
    New-FlowEdge 'gateway'  'orders'
    New-FlowEdge 'orders'   'payments'
    New-FlowEdge 'orders'   'db'
    New-FlowEdge 'payments' 'db'
    New-FlowEdge 'payments' 'queue'
    New-FlowEdge 'queue'    'notify'
)

New-FlowGraph -Nodes $nodes -Edges $edges -Layout TopDown -BoxStyle Rounded |
    Show-FlowGraph
```

### Save plain ASCII to file

```powershell
New-FlowGraph -Nodes $nodes -Edges $edges `
    -Layout Tree -BoxStyle Ascii -ConnStyle Ascii -UseColor $false |
    ConvertTo-FlowGraph |
    Out-File diagram.txt -Encoding utf8
```

---

## Module Structure

```
Flowgraph/
├── Flowgraph.psd1          # Module manifest
├── Flowgraph.psm1          # Root module (dot-sources all files)
├── Private/
│   ├── Engine.ps1          # Layout engine, theme resolver, ANSI colors
│   └── helpers/            # Color, gradient, clap, and ASCII token utilities
├── Public/
│   ├── New-FlowNode.ps1
│   ├── New-FlowEdge.ps1
│   ├── New-FlowGraph.ps1
│   └── Show-FlowGraph.ps1  # ConvertTo-FlowGraph lives here too
└── examples.ps1
```
