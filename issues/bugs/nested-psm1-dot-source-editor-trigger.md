# Bug Report: Nested `.psm1` Dot-Sourcing Triggers External Text Editor on Module Import

- **Status**: Resolved
- **Date**: 2026-08-27
- **Component**: `rivet.psm1`, `scripts/helpers/flowgraph/`
- **Impact**: Importing the `rivet` module caused the user's default text editor to open `flowgraph.psm1`.

---

## 1. Description

When executing `Import-Module ./rivet.psd1` or `Import-Module ./rivet.psm1`, the default text editor configured in the host environment unexpectedly opened `scripts/helpers/flowgraph/flowgraph.psm1` in a new window or tab.

---

## 2. Root Cause

1. **Direct Dot-Sourcing of `.psm1` Module Files**:
   `rivet.psm1` maintains a `$runtimeFiles` array of script dependencies to dot-source at initialization. When the `flowgraph` helper was introduced, `[System.IO.Path]::Combine($helperRoot, 'flowgraph', 'flowgraph.psm1')` was added to `$runtimeFiles`.
   
2. **Editor and Shell Hook Interception**:
   In PowerShell development environments (including VS Code and terminal editors with language server or file association extensions), evaluating or dot-sourcing a secondary module manifest/script (`.psm1`) inside an active module loader execution context can trigger workspace editor hooks that treat the target file path as an edit target rather than pure script execution.

3. **Linux Path Case Sensitivity**:
   `flowgraph.psm1` was internally calling `Get-ChildItem -Path "$PSScriptRoot/Private"` and `"$PSScriptRoot/Public"` with uppercase path names, failing to locate the actual lowercase `private/` and `public/` directories on case-sensitive Linux filesystems.

---

## 3. Resolution

1. **Follow the Pure File-Per-Cmdlet Loader Architecture**:
   Refactored [`rivet.psm1`](file:///home/sgkens/devspace/projects/web/_repo/staticcanvas/lume/rivet/rivet.psm1) to dot-source the underlying concrete `.ps1` function files directly instead of dot-sourcing the nested `.psm1` module file:
   - `scripts/helpers/flowgraph/private/Engine.ps1`
   - `scripts/helpers/flowgraph/public/New-FlowNode.ps1`
   - `scripts/helpers/flowgraph/public/New-FlowEdge.ps1`
   - `scripts/helpers/flowgraph/public/New-FlowGraph.ps1`
   - `scripts/helpers/flowgraph/public/Show-FlowGraph.ps1`
   - `scripts/Show-RivetFlowGraph.ps1`

2. **Standalone Fallback Loader**:
   Updated [`scripts/Show-RivetFlowGraph.ps1`](file:///home/sgkens/devspace/projects/web/_repo/staticcanvas/lume/rivet/scripts/Show-RivetFlowGraph.ps1) to load the same concrete `.ps1` files when executed standalone outside the root module context.

3. **Strict Mode Property Initialization**:
   Initialized `Meta`, `Style`, and `Label` keys to explicit `$null` fallbacks in `New-FlowNode.ps1` and `New-FlowEdge.ps1` to prevent property lookup exceptions when running under `Set-StrictMode -Version Latest`.

4. **Linux Case-Sensitivity Fix**:
   Corrected directory paths in `flowgraph.psm1` to use lowercase `private` and `public`.

---

## 4. Verification

- Executed `Import-Module ./rivet.psd1 -Force` in PowerShell: imported cleanly with zero editor windows spawned.
- Executed full Pester test suite (`Invoke-Pester -Path ./tests/Rivet.Tests.ps1`): all 45 test assertions passed.
