# TUI Design Codex

A growing reference library of terminal UI layouts for CLI/TUI apps. Every design here is built by computing padding from measured content length — never by hand-counting spaces — so borders stay aligned no matter what data lands inside them. See **Rendering notes** below before adding your own.

Companion file: `tui-design-codex.html` — the same entries rendered visually, with category filtering, a palette reference, and copy-to-clipboard. Keep both in sync as you add designs (see **Adding new entries** at the bottom).

## Index

| Code | Category | Philosophy |
|------|----------|------------|
| `PLA` | [Plain](#plain) | ASCII-only, zero dependencies, works on any terminal. |
| `MIN` | [Minimal](#minimal) | Thin rules, huge whitespace, one restrained accent. |
| `DEV` | [Dev](#dev) | Dense, tabbed, status-badge driven — a tool for tools. |
| `HAC` | [Hacker](#hacker) | Green/amber-on-black, raw streams, all-caps. |
| `ELE` | [Elegant](#elegant) | Rounded corners, soft spacing, muted accents. |
| `RET` | [Retro / CRT](#retro--crt) | Double-line borders, BBS / phosphor energy. |
| `BRU` | [Brutalist](#brutalist) | Solid block glyphs, thick borders, no mercy. |
| `DAS` | [Dashboard](#dashboard) | Multi-panel splits, sparklines, gauges. |
| `NEO` | [Neon / Electric](#neon--electric) | Saturated multi-hue, glow-friendly, high energy. |

Numbering: `CAT-NN`, zero-padded, sequential per category. Never reuse a retired number. Each entry is also tagged **full border**, **partial border**, or **borderless** — all three are intentional design choices, not gaps to fill in.

---

## Rendering notes: tear-free output

Every box below is built the same way: **measure the plain content first, pad to a fixed inner width second, apply color or style last.** That ordering is the whole fix. Two things break it in real terminal apps:

1. **Measuring after coloring.** ANSI escape codes (`\x1b[32m`, etc.) are characters as far as `.Length`/`len()` is concerned, but they draw zero columns on screen. If you pad a string that already has color codes in it, you're padding based on a number bigger than what the terminal actually renders — and the right-hand border drifts left every time the color changes. Always strip escape codes (or just don't apply them yet) before computing padding.
2. **Assuming 1 character = 1 column.** Most box-drawing glyphs, plain ASCII, and Latin text are single-width, which is why this codex avoids emoji and CJK inside bordered panels — they're the most common source of real screen tear, since many render as double-width in some terminals and single-width in others. If you need them, measure with a wide-character-aware width function, not `.Length`.

A minimal PowerShell version of the guard used to build every block in this file:

```powershell
function Get-VisibleWidth {
    param([string]$Text)
    # Strip ANSI escape sequences before measuring — color must never affect padding math
    ($Text -replace "`e\[[0-9;]*m", '').Length
}

function Pad-Line {
    param([string]$Text, [int]$Width)
    $visible = Get-VisibleWidth $Text
    if ($visible -gt $Width) { throw "content too wide: $visible > $Width (line: $Text)" }
    $Text + (' ' * ($Width - $visible))
}

# build content first, pad against ONE shared width constant, color last
$innerWidth = 50
$row = Pad-Line " CPU 12%  ok" $innerWidth
$colored = "`e[32m$row`e[0m"   # color applied AFTER padding, never before
```

The same rule applies to every top/bottom rule and every internal divider in a box: derive their length from the same width constant the content rows use, never retype it. That's specifically what fixes the classic bug where a footer or bottom rule ends up one or two columns short of the rows above it — this codex's `PLN-03` note calls that out directly since it's exactly the bug this pass corrected.

---

## Color palette library

Named, reusable palettes — apply any of these to any category above. Each gives roles for background, panel, border, text, dim text, and one or more accents.

### Vibrant
*Punchy, saturated multi-hue — playful dashboards and game-like TUIs.*

| Role | Hex |
|------|-----|
| Background | `#0d0d12` |
| Panel | `#17171e` |
| Border | `#2a2a35` |
| Text | `#f1f1f6` |
| Dim text | `#8a8a9a` |
| Accent — magenta | `#ff2fb0` |
| Accent — cyan | `#21e6ff` |
| Accent — yellow | `#ffe83d` |
| Accent — green | `#3dff7a` |

### Electric
*Narrow-hue neon voltage — glow/shadow friendly, reads as "always on".*

| Role | Hex |
|------|-----|
| Background | `#06060a` |
| Panel | `#0e0e16` |
| Border | `#20202e` |
| Text | `#eaf6ff` |
| Dim text | `#5c6b7a` |
| Accent — electric blue | `#00e5ff` |
| Accent — electric purple | `#b026ff` |
| Accent — hot pink | `#ff006e` |

### Simple / Mono
*Grayscale only, one optional accent — the safest palette for any terminal.*

| Role | Hex |
|------|-----|
| Background | `#0e0e10` |
| Panel | `#151517` |
| Border | `#2b2b2e` |
| Text | `#e4e4e4` |
| Dim text | `#6b6b6b` |
| Accent — accent (optional) | `#ffffff` |

### Phosphor Green
*Classic single-color CRT green — the Hacker category default.*

| Role | Hex |
|------|-----|
| Background | `#080a08` |
| Panel | `#0c0f0c` |
| Border | `#1a2a1a` |
| Text | `#39ff14` |
| Dim text | `#1f7a0e` |
| Accent — alert red | `#ff3b3b` |

### Amber CRT
*Warm phosphor amber — the Retro/BBS category default.*

| Role | Hex |
|------|-----|
| Background | `#0a0700` |
| Panel | `#120d00` |
| Border | `#3a2a00` |
| Text | `#ffb000` |
| Dim text | `#8a6000` |
| Accent — highlight | `#ffd766` |

### Brass / Elegant
*Warm, muted, low-saturation — the Elegant category default.*

| Role | Hex |
|------|-----|
| Background | `#111214` |
| Panel | `#17181c` |
| Border | `#2a2c30` |
| Text | `#d7dce1` |
| Dim text | `#6d7680` |
| Accent — brass | `#c9a876` |
| Accent — soft amber | `#e8b968` |

### Dev Blue
*Cool, high-legibility — the Dev category default; pairs with [OK]/[WARN]/[ERR].*

| Role | Hex |
|------|-----|
| Background | `#0c0d10` |
| Panel | `#131419` |
| Border | `#22252c` |
| Text | `#d7dce1` |
| Dim text | `#6d7680` |
| Accent — info blue | `#4fc3f7` |
| Accent — ok green | `#3ddc84` |
| Accent — warn amber | `#f5c451` |
| Accent — err red | `#ff5c5c` |

### Alert / Brutalist
*Maximum contrast, inverted-friendly — the Brutalist category default.*

| Role | Hex |
|------|-----|
| Background | `#000000` |
| Panel | `#0a0a0a` |
| Border | `#ffffff` |
| Text | `#ffffff` |
| Dim text | `#9a9a9a` |
| Accent — alert red | `#ff3b3b` |

---

## Plain

ASCII-only, zero dependencies, works on any terminal.

### PLN-01 — Task List Menu
*App type: Todo / task manager · full border*

```
+--------------------------------------------------+
| TASKS                            [3 pending]     |
+--------------------------------------------------+
| [ ] Write quarterly report         due mon       |
| [x] Review PR #482                    closed     |
| [ ] Update changelog                    due wed  |
| [ ] Fix build on aarch64                   -     |
+--------------------------------------------------+
| a:add  d:done  x:delete  q:quit                  |
+--------------------------------------------------+
```
- **Layout:** Single fixed-width panel, header/body/footer split by full-width rules.
- **Colors:** None required; if available, reserve one color for the [x] done state only.
- **Use case:** Task runners, checklist tools, anything that must degrade gracefully with no color/Unicode support.

### PLN-02 — System Status Report
*App type: Status / healthcheck · full border*

```
+==================================================+
|  SYSTEM STATUS                       2026-08-26  |
+==================================================+
|  CPU      : 12%  ok                              |
|  MEMORY   : 3.2G / 16G  ok                       |
|  DISK     : 210G / 500G  ok                      |
|  NETWORK  : up  12ms                             |
+--------------------------------------------------+
|  SERVICES                                        |
|    nginx        running                          |
|    postgres     running                          |
|    redis        stopped   <- check               |
+==================================================+
```
- **Layout:** Double-rule (=) for section breaks, single-rule (-) for subsections, two-column key/value alignment.
- **Colors:** None needed; the <- annotation carries the warning instead of color.
- **Use case:** Healthcheck CLIs, doctor commands, CI summary output piped to a log file with no TTY.

### PLN-03 — Simple File Browser
*App type: File manager · full border*

```
+---------------------------+--------------------+
| /home/user/projects       | preview            |
+---------------------------+--------------------+
| ..                        |                    |
| > agentworktree/          | select a file to   |
|   dcp/                    | preview contents   |
|   drift/                  |                    |
|   README.md               |                    |
|   Makefile                |                    |
+---------------------------+--------------------+
| j/k move  enter open  q quit                   |
+------------------------------------------------+
```
- **Layout:** Two fixed columns (~57/43). ">" marks selection instead of inverse video. Every rule — including the footer divider — is computed from the same total-width constant, which is the fix for the classic mismatched-bottom-border bug.
- **Colors:** None; selection is marker-based so it works in monochrome.
- **Use case:** Minimal file pickers embedded in larger tools — commit hooks, install wizards.

### PLN-04 — Simple Invoice Table
*App type: Table / record viewer · full border*

```
+====+======================+=========+
|  INVOICE #0042                      |
+====+======================+=========+
| QTY| ITEM                 | PRICE   |
+----+----------------------+---------+
| 2  | PSAnsi license       | $0.00   |
| 1  | Drift support        | $40.00  |
| 3  | RavenUI theme        | $15.00  |
+----+----------------------+---------+
|  TOTAL                     $85.00   |
+====+======================+=========+
```
- **Layout:** ASCII column grid with a full-width header/total row spanning all columns — a common source of tear if the span width isn't derived from the sum of the column widths plus separators.
- **Colors:** None; pure ASCII works over any connection.
- **Use case:** Line-item tables, billing/report CLIs, anything that must render identically on a dumb terminal.

## Minimal

Thin rules, huge whitespace, one restrained accent.

### MIN-01 — Focus Timer
*App type: Pomodoro / timer · borderless*

```

                    25:00

                  ● ● ● ○ ○

            [ pause ]    [ skip ]

```
- **Layout:** No border at all — content is centered in the terminal with generous vertical padding.
- **Colors:** Filled dots use a single accent (soft amber); everything else is default foreground.
- **Use case:** Single-purpose utilities where the terminal window itself is the whole app — timers, counters, single-metric watchers.

### MIN-02 — Single Note Editor
*App type: Scratchpad / notes · full border*

```
┌────────────────────────────────────────┐
│ untitled                               │
│                                        │
│ Meeting notes go here.                 │
│                                        │
│                                        │
│                                        │
└────────────────────────────────────────┘
  ⌘s save   esc close
```
- **Layout:** One thin-rule box computed from a single width constant, title line separated only by a blank row, keybinds live outside the box (not part of the bordered region).
- **Colors:** Border in dim gray, text full-contrast, no accent color at all.
- **Use case:** Scratch buffers, commit-message editors, quick-capture tools.

### MIN-03 — Command Prompt (empty state)
*App type: REPL / shell · borderless*

```

  ~/projects/drift

  ›

```
- **Layout:** No box, just an indented path and a single prompt glyph (›) instead of $.
- **Colors:** Path dimmed, prompt glyph in accent color, cursor is the only bright element.
- **Use case:** The empty/idle state of any REPL — proof a minimal design still needs to define what "nothing is happening" looks like.

### MIN-04 — System Tray Panel
*App type: Status summary · full border*

```
┌──────────────────────────────────┐
│                                  │
│  battery      87%                │
│  wifi         connected          │
│  volume       muted              │
│                                  │
└──────────────────────────────────┘
```
- **Layout:** A fully-enclosed thin-rule box — the category's full-border reference point, proving minimal doesn't require borderless.
- **Colors:** Border in dim gray; a single accent marks the one value that needs attention, everything else stays neutral.
- **Use case:** Compact status popovers, tray-style summaries, a persistent corner widget in a larger layout.

## Dev

Dense, tabbed, status-badge driven — a tool for tools.

### DEV-01 — Git Log / Branch Graph
*App type: Git client · full border*

```
┌─ log ─┬─ branches ─┬─ stash ──────────────────────┐
│ * a1c9f2  feat: quad-hybrid render pipeline       │
│ * 88de11  fix: memory leak in tag resolver        │
│ |\                                                │
│ | * 7cb410  wip: renderer prototype               │
│ |/                                                │
│ * 004ab2  chore: bump deps                        │
├───────────────────────────────────────────────────┤
│ HEAD -> main   origin/main   3 ahead              │
└───────────────────────────────────────────────────┘
```
- **Layout:** Tabbed top border built from labeled segments joined at exact character offsets, graph column fixed-width on the left, commit message flows right.
- **Colors:** Graph lines in muted blue, hashes in dim gray, "HEAD ->" in accent bold.
- **Use case:** Git TUIs (lazygit-style), branch visualizers, PR review tools.

### DEV-02 — Build & Test Runner Output
*App type: Test runner · full border*

```
┌ pester ▸ AgentWorktree.Tests.ps1 ─────────────────┐
│ [OK]   New-Worktree creates isolated branch       │
│ [OK]   Remove-Worktree cleans up refs             │
│ [WARN] Sync-Worktree skipped (no remote)          │
│ [ERR]  Merge-Worktree: conflict in tests/fixture  │
├───────────────────────────────────────────────────┤
│ 24 passed   1 warned   1 failed   ·   2.4s        │
└───────────────────────────────────────────────────┘
```
- **Layout:** Breadcrumb title (suite ▸ file) embedded directly in the border, left-aligned status tags at fixed width so messages align.
- **Colors:** [OK] green, [WARN] amber, [ERR] red — the phellams status-tag convention.
- **Use case:** Pester/pytest/jest-style runners, CI log viewers, lint output.

### DEV-03 — API Request Inspector
*App type: HTTP client / debugger · full border*

```
┌ request ──────────────────────────────────────────┐
│ POST /api/v4/projects/482/pipelines               │
│ status  200                          142ms        │
├─ headers ─────────────────────────────────────────┤
│ content-type: application/json                    │
│ x-ratelimit-remaining: 1998                       │
├─ body ────────────────────────────────────────────┤
│ { "id": 8841, "status": "pending" }               │
└───────────────────────────────────────────────────┘
```
- **Layout:** Stacked sections with inline mini-headers rather than full-width dividers — saves vertical space while every row still resolves to the same total width.
- **Colors:** Method (POST) in accent, 2xx status in green, JSON keys dimmed vs. string values full-contrast.
- **Use case:** HTTPie-style TUIs, GitLab/GitHub API wrappers, webhook debuggers.

### DEV-04 — Dependency Tree
*App type: Package manager / resolver · full border*

```
┌────────────────────────────────────────────┐
│ deps ▸ phellams-automator                  │
├────────────────────────────────────────────┤
│ PH.ErrorReporting          ^2.1.0          │
│  └─ PSAnsi                  ^1.4.2         │
│ DCP                        ^0.9.0          │
│  └─ PSAnsi                  ^1.4.2  dup    │
├────────────────────────────────────────────┤
│ 4 packages, 1 duplicate resolved           │
└────────────────────────────────────────────┘
```
- **Layout:** Indented tree rows inside a fully bordered panel, with a duplicate-resolution warning called out inline rather than in a separate color-only signal.
- **Colors:** Package names full-contrast, version ranges dimmed, "dup" flagged in amber.
- **Use case:** npm/nuget/cargo-style dependency inspectors, lockfile explainers.

## Hacker

Green/amber-on-black, raw streams, all-caps.

### HAK-01 — Network Scanner
*App type: Port / network scanner · partial border*

```
[SCAN] target 10.0.0.0/24 ................ 62%
------------------------------------------------
10.0.0.1    up     22/tcp   ssh    OpenSSH 9.3
10.0.0.14   up     80/tcp   http   nginx
10.0.0.14   up     443/tcp  https  nginx
10.0.0.22   filtered
10.0.0.31   up     3306/tcp mysql
------------------------------------------------
[####################............] 41/64 hosts
```
- **Layout:** Left-aligned data columns under a plain rule (top/bottom only, no side borders) with an ASCII progress bar rather than a Unicode block gauge — reads as a raw tool, not a polished dashboard.
- **Colors:** Phosphor green on near-black; filtered/closed rows dim to gray.
- **Use case:** nmap-style scanners, recon tools, pentest utilities.

### HAK-02 — System Intrusion Monitor
*App type: Security monitor · partial border*

```
█▓▒░ INTRUSION MONITOR ░▒▓█
────────────────────────────
> AUTH FAIL   root@10.4.2.9   x14   [BLOCKED]
> AUTH FAIL   admin@10.4.2.9  x3
> PORT SCAN   10.4.2.9 -> 10.4.2.0/24
> RULE HIT    fw::deny_burst applied
────────────────────────────
THREAT LEVEL: [■■■■■■□□□□] ELEVATED
```
- **Layout:** The █▓▒░ fade is used once, purely as a title flourish — do not repeat it elsewhere on the same screen. Rules above/below only, no side borders.
- **Colors:** Base green; [BLOCKED] and ELEVATED escalate to red as the only warm color on screen.
- **Use case:** fail2ban-style dashboards, SOC/NOC alert feeds, IDS front-ends.

### HAK-03 — Log Tail / Live Stream
*App type: Log tail · borderless*

```
root@node-07:~$ tail -f /var/log/syslog
Aug26 03:14:07 kernel: eth0 link up
Aug26 03:14:09 sshd: session opened uid=0
Aug26 03:14:12 cron: (root) CMD (backup.sh)
Aug26 03:14:44 sshd: session closed
_
```
- **Layout:** No chrome at all — meant to look exactly like a real terminal, prompt included, with a blinking block cursor on the last line.
- **Colors:** Timestamps dimmed, process names in accent, rest in default green/white.
- **Use case:** tail -f, journalctl streams, real-time log viewers.

### HAK-04 — Password Cracking Progress
*App type: Security tool / brute-force UI · full border*

```
+----------------------------------------+
| root@target : cracking shadow.bak      |
|                                        |
| trying: correcthorsebatterystaple      |
| rate: 4.2M/s     tried: 8,204,112      |
| [############............] 44%         |
+----------------------------------------+
```
- **Layout:** The category's full-border reference point: same phosphor-green register as HAK-01–03, but fully enclosed for contexts that need a defined panel edge (embedded in a larger multi-pane layout, for example).
- **Colors:** Phosphor green text, ASCII bar fill in the same green, border in dim green rather than full brightness.
- **Use case:** Brute-force/benchmark tools, any long-running rate-limited operation that needs a persistent frame.

## Elegant

Rounded corners, soft spacing, muted accents.

### ELG-01 — Project Dashboard Card
*App type: Project overview · full border*

```
╭───────────────────────────────────────╮
│  Drift                                │
│  PowerShell web framework             │
│                                       │
│  progress   ●●●●●●●○○○   72%          │
│  status     active                    │
│  updated    2 days ago                │
│                                       │
╰───────────────────────────────────────╯
```
- **Layout:** Rounded box, label/value pairs left-aligned with a fixed label column, one blank line above and below the metrics block.
- **Colors:** Border in soft gray, filled progress dots in muted brass, empty dots in low-contrast gray.
- **Use case:** Project/repo overview cards, the "home screen" of a multi-project TUI.

### ELG-02 — Settings Panel
*App type: Preferences / config · full border*

```
╭─ preferences ──────────────────────────╮
│                                        │
│  theme          ›  midnight            │
│  font           ›  IBM Plex Mono       │
│  accent         ›  brass               │
│  telemetry      ›  off                 │
│                                        │
╰────────────────────────────────────────╯
```
- **Layout:** Section title embedded in the top border at an exact offset, "›" as the value chevron instead of a colon — reads softer.
- **Colors:** Labels dimmed, values full-contrast, chevron in accent.
- **Use case:** Any settings/config screen where the tone should feel considered rather than utilitarian.

### ELG-03 — Weekly Journal
*App type: Log / journal · full border*

```
╭────────────────────────────────────────╮
│  week of aug 24                        │
│  ────────────────────────────────────  │
│  mon   shipped psansi v2               │
│  tue   reviewed ravenui palette        │
│  wed   —                               │
│                                        │
╰────────────────────────────────────────╯
```
- **Layout:** Thin internal rule under the title only, not between every row. Empty days shown as an em-dash rather than left blank.
- **Colors:** Day labels dimmed and right-padded to align, entries full-contrast.
- **Use case:** Devlogs, changelogs-as-you-go, standup-note tools.

### ELG-04 — CI Status Summary
*App type: Build status widget · full border*

```
╭────────────────────────────────────╮
│                                    │
│  build      ● passing              │
│  coverage   ●●●●●●●●○○  81%        │
│  version    2.3.0                  │
│                                    │
╰────────────────────────────────────╯
```
- **Layout:** A small, dense rounded card — proof the elegant register scales down to a compact status widget, not just full dashboards.
- **Colors:** Passing status in a soft green dot, coverage bar in brass, version number dimmed.
- **Use case:** Compact CI badges inside a larger TUI, PR-status widgets, README-adjacent terminal badges.

## Retro / CRT

Double-line borders, BBS / phosphor energy.

### RET-01 — BBS Main Menu
*App type: Main menu / launcher · full border*

```
╔══════════════════════════════════════════╗
║          W E L C O M E   B B S           ║
╠══════════════════════════════════════════╣
║  [1] Message Boards                      ║
║  [2] File Library                        ║
║  [3] Door Games                          ║
║  [4] Who's Online                        ║
║  [5] Logoff                              ║
╠══════════════════════════════════════════╣
║  Enter selection:  _                     ║
╚══════════════════════════════════════════╝
```
- **Layout:** Double-line box throughout, letter-spaced title, numbered options with no icons — text does all the work.
- **Colors:** Amber or classic green on black; no secondary accent, everything is the one phosphor color.
- **Use case:** Launcher menus, main-menu screens for multi-mode CLIs, nostalgia-driven dev tools.

### RET-02 — Retro File Manager
*App type: Dual-pane file manager · full border*

```
╔═ LEFT ══════════════╦═ RIGHT ═════════════╗
║ C:\DOS\             ║ A:\BACKUP\          ║
║  COMMAND.COM   47K  ║  README.TXT     2K  ║
║  AUTOEXEC.BAT   1K  ║  DATA.ZIP     118K  ║
╠═════════════════════╩═════════════════════╣
║ F5 Copy  F6 Move  F8 Delete  F10 Quit     ║
╚═══════════════════════════════════════════╝
```
- **Layout:** Literal Norton-Commander dual pane with a T-junction where panes meet the footer — the exact character offset where columns meet the divider is computed, not eyeballed, so the joint never tears.
- **Colors:** Amber or cyan on black, function-key footer in inverse video.
- **Use case:** Dual-pane file managers (a direct homage), disk utilities.

### RET-03 — ANSI Splash / Boot Screen
*App type: Splash / boot screen · full border*

```
╔══════════════════════════════════════════╗
║                                          ║
║     ▄▄▄▄▄  ▄▄▄▄▄  ▄  ▄  ▄▄▄▄▄            ║
║     █   █  █      █  █  █                ║
║     █▄▄▄▀  █▄▄▄▄  █▄▄█  █▄▄▄▄            ║
║                                          ║
║        press any key to continue         ║
╚══════════════════════════════════════════╝
```
- **Layout:** The block-letter logo is the only content — everything else is empty space inside a double-line frame.
- **Colors:** Logo in full accent color, "press any key" dimmed and optionally blinking.
- **Use case:** App launch splash screens, --version/banner output, installer welcome screens.

### RET-04 — Loading Screen
*App type: Progress / loading screen · full border*

```
╔════════════════════════════════════════╗
║                LOADING                 ║
║                                        ║
║  [██████████████████░░░░░░░░░░] 64%    ║
║                                        ║
║             please wait...             ║
╚════════════════════════════════════════╝
```
- **Layout:** Centered label, centered ASCII block-and-shade progress bar, centered footer line — every centered string is padded from its own measured length so the visual center never drifts as the percentage changes.
- **Colors:** Amber block fill, unfilled portion in a dim shade character rather than blank space so the bar's total length reads as fixed.
- **Use case:** Installer/loading screens, any long-running step that wants retro ceremony instead of a bare percentage.

## Brutalist

Solid block glyphs, thick borders, no mercy.

### BRU-01 — Raw Metrics Grid
*App type: System metrics · full border*

```
██████████████████████████████████████████
█ CPU  87% █ MEM  61% █ DISK 94% █ NET 3%█
██████████████████████████████████████████
█ LOAD 4.82   1.90   0.77                █
██████████████████████████████████████████
```
- **Layout:** Full block borders instead of line-drawing characters; cells separated by single block characters rather than whitespace, column widths summed exactly to the frame width.
- **Colors:** Background stays black, block borders in full white or full accent — no gray, no dimming.
- **Use case:** System-critical monitors meant to be glanced at from across a room — NOC video walls, kiosk displays.

### BRU-02 — Process Table
*App type: Process monitor · full border*

```
█████████████████████████████████████████████
█ PID   █ NAME              █ CPU    █ MEM  █
█████████████████████████████████████████████
█ 1021  █ nginx             █ 2%     █ 44M  █
█ 1188  █ postgres          █ 9%     █ 412M █
█ 2044  █ node              █ 61%    █ 180M █
█████████████████████████████████████████████
```
- **Layout:** Column separators are block glyphs, not spaces — the grid is aggressively visible; every row's cell widths are computed from the same tuple so no column ever drifts.
- **Colors:** High CPU/MEM values can invert to a solid red block background rather than colored text, staying in the block language.
- **Use case:** top/htop alternatives that want to look intentionally raw rather than polished.

### BRU-03 — Alert Wall
*App type: Alert / paging screen · full border*

```
██████████████████████████████████████████
█ !! DISK 94% !! ACT NOW !! DISK 94% !!  █
██████████████████████████████████████████
█ !! LOAD HIGH !! ACT NOW !! LOAD HIGH !!█
██████████████████████████████████████████
```
- **Layout:** The message repeats within its own row — redundancy as a design choice, legible even glanced at mid-scroll.
- **Colors:** Solid red or amber block background, black text — the inverse of every other design in this codex, on purpose.
- **Use case:** Paging/incident screens meant to be unmissable, never a default idle state.

### BRU-04 — Confirm / Kill Dialog
*App type: Confirmation modal · full border*

```
████████████████████████████████████
█ TERMINATE PROCESS 2044?          █
████████████████████████████████████
█  [Y] confirm    [N] cancel       █
████████████████████████████████████
```
- **Layout:** A small fully block-bordered modal — proof the brutalist register works for a two-line confirmation, not only full-screen monitors.
- **Colors:** Same solid-block frame as the rest of the category; no separate "modal" styling language introduced.
- **Use case:** Destructive-action confirmations (kill process, delete volume, force push) where the visual weight should match the stakes.

## Dashboard

Multi-panel splits, sparklines, gauges.

### DSH-01 — Ops Dashboard
*App type: Ops / metrics dashboard · full border*

```
┌─ requests/s ────────┬─ errors ──┬─ latency ───┐
│ ▂▃▅▇▆▄▃▂▃▅▇█▆▄▃▂▃   │ 0.4%      │ 84ms p50    │
├─────────────────────┴───────────┴─────────────┤
│ nodes    ●●●●●●●○○○  7/10 healthy             │
│ queue    142 jobs                             │
│ deploys  3 today   last: 14:02 main@a1c9f2    │
└───────────────────────────────────────────────┘
```
- **Layout:** Three-up sparkline row on top with unequal widths — the sparkline panel is widest since it carries the most information — full-width status rows below, joined at a divider computed from the same three widths.
- **Colors:** Sparkline in accent blue, error % in amber/red by threshold, node dots green/gray for healthy/unhealthy.
- **Use case:** The "home screen" of an ops TUI — k9s/lazydocker-style landing views.

### DSH-02 — Kanban Board
*App type: Task board · full border*

```
┌─ TODO ───────┬─ DOING ──────┬─ DONE ───────┐
│ fix ci flake │ tag resolver │ psansi v2    │
│ write docs   │ brand kit    │ hotfix #482  │
│              │              │ deps bump    │
└──────────────┴──────────────┴──────────────┘
```
- **Layout:** Three equal-width columns; cards are just text rows with no per-card border to keep the board scannable at a glance.
- **Colors:** Column headers in distinct muted accents so the eye tracks state without reading the header text.
- **Use case:** Terminal kanban tools, sprint boards, PR-review-queue views.

### DSH-03 — Server Fleet Monitor
*App type: Fleet / cluster monitor · full border*

```
┌─ node-01 ─┬─ node-02 ─┬─ node-03 ─┬─ node-04 ─┐
│ cpu ▓▓▓░░ │ cpu ▓▓▓▓▓ │ cpu ▓░░░░ │ cpu ▓▓░░░ │
│ up  14d   │ up  2d    │ up  61d   │ up  9d    │
│ ok        │ hot       │ ok        │ ok        │
└───────────┴───────────┴───────────┴───────────┘
```
- **Layout:** N equal columns that scale horizontally with fleet size — reach for this pattern whenever the entity count is dynamic, not fixed; the join glyphs are generated per-column so adding a 5th node never desyncs the header.
- **Colors:** Block-bar fills scale from green through amber to red by load; the one-word status line repeats the same signal in text for accessibility.
- **Use case:** Fleet dashboards, container/pod grids, CI runner fleets.

### DSH-04 — Single-Panel Throughput
*App type: Metrics widget · full border*

```
┌────────────────────────────────────────────┐
│ THROUGHPUT                                 │
│ ▂▃▅▇▆▄▃▂▃▅▇█▆▄▃▂▃▅▇▆▄▃▂  842 rps           │
├────────────────────────────────────────────┤
│ p50  84ms      p99  310ms      err 0.4%    │
└────────────────────────────────────────────┘
```
- **Layout:** One fully bordered panel rather than a multi-column split — the category's full-border reference point for contexts where a single metric deserves the whole frame.
- **Colors:** Sparkline in accent, the trailing summary number in full-contrast bold, secondary stats dimmed on the row below a divider.
- **Use case:** Embeddable single-metric widgets inside a larger dashboard grid, or a standalone `watch`-style tool.

## Neon / Electric

Saturated multi-hue, glow-friendly, high energy.

### NEO-01 — Now Playing / Media Player
*App type: Music / media player · full border*

```
┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃             ▸▸ NOW PLAYING             ┃
┃                                        ┃
┃  Midnight Circuit                      ┃
┃  synthwave // 03:12                    ┃
┃                                        ┃
┃  [▬▬▬▬▬▬▬▬•──────] 01:24 / 03:12       ┃
┃                                        ┃
┃               ⏮   ▶   ⏭                ┃
┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛
```
- **Layout:** Heavy-line (bold) box drawing for extra visual weight, centered title and centered transport controls, progress bar built from filled/unfilled glyphs of guaranteed-equal total length.
- **Colors:** Title in electric blue, progress fill in hot pink, transport glyphs in electric purple — three accents used deliberately, not randomly.
- **Use case:** Media players, audio visualizers, anything where the frame itself should feel like it's "on".

### NEO-02 — Game HUD
*App type: Game status overlay · full border*

```
┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃ HP  ♥♥♥♥♥♥♥♥♡♡   LVL 14                  ┃
┃ MP  ♦♦♦♦♦♦♦♦♦♦   XP  8,412               ┃
┣━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┫
┃                                          ┃
┃ [!] boss encounter in 20m                ┃
┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛
```
- **Layout:** Two stat rows (HP/MP) separated from an alert row by a divider; heart/diamond glyphs are counted like any other character so the bar never desyncs from its label.
- **Colors:** HP in hot pink/red, MP in electric blue, the boss-alert row in yellow as the one warning color in an otherwise cool palette.
- **Use case:** Terminal game HUDs, roguelike status bars, health/resource overlays.

### NEO-03 — Chat / IRC Client
*App type: Chat client · full border*

```
┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃ #general                               ┃
┃                                        ┃
┃ kai      shipped the neon variant      ┃
┃ row      that gradient is unreal       ┃
┃ kai      css or ansi 256?              ┃
┃ row      ansi 256, no gradients irl    ┃
┃                                        ┃
┃ › type a message_                      ┃
┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛
```
- **Layout:** Channel name as a plain header row, message rows left-aligned with a fixed username column, live input row at the bottom with a block cursor.
- **Colors:** Usernames in alternating accent colors (cycle electric blue / hot pink) so speakers are distinguishable without re-reading the name.
- **Use case:** IRC/Matrix/Slack-style terminal chat clients, pairing tools with a chat sidebar.

### NEO-04 — Upload / Transfer Progress
*App type: File transfer widget · full border*

```
┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃            ELECTRIC UPLOAD             ┃
┃                                        ┃
┃ [██████████████░░░░░░] 70%             ┃
┃ 14.2MB / 20.4MB    3.1 MB/s            ┃
┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛
```
- **Layout:** Centered title, then a left-aligned progress bar and stat line — deliberately mixing centered and left-aligned content inside one frame to show the technique still holds as long as every row is padded to the same width.
- **Colors:** Bar fill in electric blue transitioning conceptually toward green near completion; speed/size line dimmed.
- **Use case:** Upload/download progress in CLI tools, sync clients, deploy-progress widgets.

---

## Adding new entries

When you (or a generated TUI) produce a design worth keeping, append it here using this template, then mirror it into the `DESIGNS` array in `tui-design-codex.html`:

```
### CAT-NN — Title
*App type: what kind of app this suits · full border | partial border | borderless*

\`\`\`
(raw ascii/unicode block — build it by padding each row to ONE shared width
constant computed from the row's plain content, per Rendering notes above)
\`\`\`
- **Layout:** how the screen is structured — panels, alignment, spacing rules.
- **Colors:** which palette (see library above) or specific hex values, and where.
- **Use case:** what kind of CLI/TUI app this pattern fits.
```

Guidelines for new entries:
- Before pasting a new block in, run it through the same check the generator used for this file: every line that starts with a border glyph must be the exact same length. A one-character mismatch is a tear, not a style choice.
- Keep one entry per screen *state*, not per app — a settings panel and that same app's error state are two entries.
- Tag the border style explicitly (`full` / `partial` / `borderless`) — this codex intentionally keeps a few of each per category rather than defaulting to full borders everywhere.
- If a design doesn't cleanly fit an existing category, that's a signal to consider a new category rather than forcing it — add a row to the Index table if you do, the way `neon` was added here.
- Numbers are permanent once assigned. If a design is replaced by a better version of the same idea, add it as a new number and note `(supersedes CAT-NN)` rather than editing history away.
