# DevTracker: Generic Completion Reporting, Clean `.rivet/` Workspace, Generic Caching & Work Item Sync

- **Document Version**: 1.2.0
- **Status**: COMPLETED
- **Target Component**: Rivet CLI, Automation & Caching Framework

---

## 1. Executive Summary

This document captures the architectural gaps, technical specifications, and implementation outcomes for four major capability enhancements to Rivet:
1. **Generic Completion Reporting System**: An elegant, non-tear ASCII TUI final report card system with orange-to-offblack gradient framing, granular execution metadata, paragraph wrapping, and `-Raw` suppression for compound `[MA]` workflows.
2. **Clean `.rivet/` Workspace Consolidation**: Centralizing Rivet-managed artifacts (`.rivet/mr.md`, `.rivet/work-items/`, `.rivet/cache/`, `.rivet/repo_meta.json`, `.rivet/repo_config.json`) with seamless backwards-compatible fallback to root locations.
3. **Generic CLI & API Cache Library (`rivet_cache.ps1`)**: High-performance, zero-dependency caching utility with memory/disk backing, TTL expiration, tag invalidation, and comprehensive telemetry metrics (hits, misses, latencies, size in bytes).
4. **Robust Issue & Work Item Synchronization**: A bidirectional synchronization engine (`Sync-RivetWorkItems.ps1`) interfacing local Markdown work items formatted with `mr.md`-style metadata tables in `.rivet/work-items/` with GitLab Issues REST APIs, supporting selective single-issue pull/push and `Sync Action: pull|push` table controls.

---

## 2. Gap Analysis

| Area | Initial State | Identified Gap | Target Architecture Implemented |
|---|---|---|---|
| **Completion Reporting** | Plain text `FINAL REPORT` console logs emitted directly at end of `Invoke-Rivet.ps1`. | Inner actions lacked unified reporting cards; compound workflows duplicated log noise; lines lacked paragraph wrapping. | Dedicated `Write-RivetReportCard.ps1` producing non-tear TrueColor gradient bordered panels with `-Raw` suppression for compound `[MA]` sub-actions. |
| **Repository Hygiene** | Configuration and artifacts (`repo_config.json`, `repo_meta.json`, `mr.md`) scattered directly in project root. | Cluttered project root and risked merge conflicts with other tooling. | Consolidate Rivet files into `.rivet/` (`.rivet/repo_config.json`, `.rivet/repo_meta.json`, `.rivet/mr.md`, `.rivet/work-items/`, `.rivet/cache/`) with automatic root fallback (`Resolve-RivetPath.ps1`). |
| **API Caching & Metrics** | Direct REST API calls without caching or latency tracking. | Heavy network load and rate limiting on frequent queries. | Dedicated `scripts/helpers/cache/rivet_cache.ps1` with in-memory + disk caching, TTL expiration, tag invalidation, and metrics telemetry. |
| **Work Items / Issues** | No native work item or issue tracking capability within Rivet. | Developers had to manually context-switch to browser to view, create, or update GitLab issues. | Native `.rivet/work-items/` table-based Markdown format (`templates/workitem.md`) with selective single-item pull/push and cache integration (`Sync-RivetWorkItems.ps1`). |

---

## 3. Detailed Specifications & Outcomes

### 3.1 Generic Completion Reporting System (`Write-RivetReportCard.ps1`)
- TrueColor orange `RGB(255, 130, 0)` to dark off-black `RGB(40, 44, 54)` linear gradient borders.
- Responsive width adaptation dynamically matching console width without screen tearing.
- Word-boundary paragraph wrapping for multi-line log explanations.
- Standardized status badges (`[SUC]`, `[ACT]`, `[SKIP]`, `[FAIL]`, `[WRN]`, `[INF]`).
- `-Raw` switch suppresses console output and returns structured `[pscustomobject]` data model for compound workflows.

### 3.2 Clean `.rivet/` Workspace Resolution (`Resolve-RivetPath.ps1`)
- Checks `.rivet/<name>` first; if present, uses it.
- Falls back to root `<name>` for seamless backward compatibility.
- Creates `.rivet/` container automatically on initial write.

### 3.3 Generic Caching Engine (`scripts/helpers/cache/rivet_cache.ps1`)
- Memory and disk-backed caching with automatic TTL expiration.
- Tag-based invalidation (`Remove-RivetCache -Tag <tag>`).
- Operational telemetry and performance metrics (`Get-RivetCacheMetrics` tracking Hits, Misses, HitRatePercentage, AverageReadMs, AverageWriteMs, DiskEntries, TotalSizeBytes).
- Higher-order execution wrapper (`Invoke-RivetCachedOperation`).

### 3.4 Work Item Table Template & Targeted Sync (`Sync-RivetWorkItems.ps1`)
- Table-based metadata header formatted identically to `templates/mr.md`:
  - `Gitlab Issue IID`, `Gitlab Issue Link`, `Sync Action` (default `pull`, can be toggled to `push`), `Status`, `Created Date`, `Last Updated Date`, `Author`, `Milestone`, `Labels`, `Title`.
- Selective pull: pulls only requested IID (e.g. `-Iid 42`) or files marked `Sync Action: pull`.
- Selective push: publishes files marked `Sync Action: push`, creates/updates remote issue, writes back assigned IID and URL, and resets `Sync Action` to `pull`.

### 3.5 SMenu Description Display Types & Card/Pager Framing (`smenu.ps1`)
- **Configurable Modes**:
  - `Card` (default): Side-by-side or stacked dedicated preview card box spanning the full height of menu items with rounded borders, title headers, and padded word-wrapped context.
  - `Inline`: Classic side-by-side label + single-line description with bottom detail bar.
  - `Minimal`: Distraction-free clean item list with single-line bottom status bar.
  - `Pager`: Expanded multi-line scrollable documentation viewport spanning the full available height.
- **Interactive Mode Cycling**:
  - `Tab` / `Shift+Tab` dynamically cycles between `Card`, `Inline`, `Minimal`, and `Pager` modes during runtime.

### 3.6 Aggregated Task Tracker Template (`templates/workitems-list.md`)
- **Dashboard & Index Overview**:
  - Aggregated companion to granular `.rivet/work-items/*.md` files, providing a bird's-eye glanceable task list.
  - Formatted with alert callouts (`[!NOTE]`, `[!CAUTION]`) and machine-parsable delimiters (`<!--rivet: generated Tasklist-->`).
  - Structured card blocks per task featuring meta links (`[#IID](url)`), last updated timestamp, assignees, date ranges, topic labels, status badges (`🟢 open` / `✅ closed`), brief summary, and nested blockquote previews of recent discussion comments.

---

## 4. Implementation Tasks

- [x] Create `devtracker-pending.md` architectural specification.
- [x] Implement `Resolve-RivetPath` helper in `scripts/helpers/data_utils/Resolve-RivetPath.ps1`.
- [x] Implement `Write-RivetReportCard.ps1` in `scripts/helpers/ui/Write-RivetReportCard.ps1`.
- [x] Implement `rivet_cache.ps1` universal caching and telemetry utility in `scripts/helpers/cache/rivet_cache.ps1`.
- [x] Implement table-based work item template in `templates/workitem.md`.
- [x] Implement aggregated task tracker dashboard template in `templates/workitems-list.md`.
- [x] Implement `Sync-RivetWorkItems.ps1` supporting table metadata, selective single-item pull/push, and cache integration.
- [x] Update `Get-RivetConfiguration.ps1`, `Initialize-RivetRepository.ps1`, `Sync-GitLabRepositoryMetadata.ps1`, `Update-MergeRequestDocumentation.ps1`, `Invoke-GitLabMergeRequest.ps1`, `Test-RivetRepository.ps1`, `jsheader.ps1`, and `Invoke-Rivet.ps1` for `.rivet/` resolution and caching.
- [x] Integrate `work-items` command, `template` command, and parameters in `Invoke-Rivet.ps1`, `Invoke-RivetMenu.ps1`, and `argumentcompleters.ps1`.
- [x] Implement `Inline`, `Minimal`, `Card`, and `Pager` description display types with dynamic `Tab` switching in `scripts/smenu.ps1`.
- [x] Update `help.ps1`, `rivet.psm1`, and `README.md`.
- [x] Add comprehensive Pester unit tests in `tests/Rivet.Tests.ps1`.
