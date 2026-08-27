# Bug Report: Interactive Menu Actions Return Errors on Execution

- **Status**: Resolved
- **Date**: 2026-08-28
- **Component**: `scripts/Invoke-RivetMenu.ps1`, `scripts/Invoke-Rivet.ps1`
- **Impact**: Executing certain menu actions (work items with labels, interactive commit, dry-run toggles, and multi-value options) threw parameter binding errors or input stream termination errors.

---

## 1. Description

When selecting and executing actions from the interactive TUI menu (`./run.ps1 menu` / `./rivet.ps1 menu`), certain submenus and workflows failed with errors upon execution:

1. **Work Items Creation with Multiple Labels**:
   Selecting **Work items & tasks** -> **Scaffold new work item** with comma-separated labels threw:
   ```
   run.ps1: Cannot bind parameter because parameter 'IssueLabels' is specified more than once.
   To provide multiple values to parameters that can accept multiple values, use the array syntax.
   For example, "-parameter value1,value2,value3".
   ```

2. **Interactive Conventional Commit Prompt Termination**:
   Selecting **Conventional Commit** -> **Commit current changes** threw an input stream EOF error because stdout/stderr redirection (`2>&1 | ForEach-Object ...`) detached the child process from active terminal stdin.

3. **Boolean Switch False Bindings**:
   Workflows with negative flags (e.g. `$p.IncludeCommitHash = $false`) were splatted as `-IncludeCommitHash False` instead of `-IncludeCommitHash:$false`, triggering positional parameter binding exceptions.

---

## 2. Root Cause

1. **Hashtable Splatting across CLI Process Boundaries**:
   Passing a hashtable `@Parameters` directly to `pwsh -File $resolvedRunner @Parameters` relies on PowerShell's native CLI argument translation. In PowerShell:
   - Array values (e.g. `@('bug', 'ui')`) are expanded into repeated switch arguments (`-IssueLabels bug -IssueLabels ui`), which `run.ps1` rejects when binding `[string[]]`.
   - Boolean `$false` values are passed as separate string values (`-IncludeCommitHash False`) rather than switch modifiers (`-IncludeCommitHash:$false`).

2. **Stdin Disconnection in Captured Workflows**:
   Capturing output via pipeline piping (`2>&1 | ForEach-Object { [string]$_ }`) redirects `StandardInput`. Interactive commands such as `Invoke-RepositoryCommit` that invoke `Read-Host` or `$host.UI.ReadLine()` cannot read interactive user keystrokes in redirected mode.

---

## 3. Resolution

1. **Typed Argument List Construction ([`scripts/Invoke-RivetMenu.ps1`](file:///home/sgkens/devspace/projects/web/_repo/staticcanvas/lume/rivet/scripts/Invoke-RivetMenu.ps1))**:
   Replaced direct hashtable splatting with structured CLI argument generation:
   - Formatted arrays as comma-separated strings (`$argList.Add(($arrayItems -join ','))`).
   - Formatted booleans using strict switch modifier syntax (`-$key` for `$true`, `-${key}:$false` for `$false`).
   - Preserved `-RepositoryRoot` as the leading explicit parameter.

2. **Interactive vs. Non-Interactive Workflow Routing**:
   Added `$isInteractive` detection for workflows requiring direct terminal console interaction (such as active Conventional Commit). Interactive commands execute directly against the active terminal handle (`& pwsh -NoLogo -NoProfile -File $resolvedRunner @argList`), while non-interactive / review commands route output through the ANSI pager.

---

## 4. Verification

- Tested `Work items & tasks` -> `Scaffold new work item` with `-IssueLabels "bug,ui"`: executed cleanly with exit code 0.
- Tested `Conventional Commit` -> `Commit current changes`: interactive prompts and descriptions display with full terminal input access.
- Executed complete Pester test suite (`Invoke-Pester -Path ./tests/Rivet.Tests.ps1`): all **67/67 tests passing** with 0 failures.
