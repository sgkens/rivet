# Bug Report: Finalized Changelog Retains Lingering `[Unreleased]` Heading

- **Status**: Resolved
- **Date**: 2026-08-28
- **Component**: `scripts/Update-ReleaseDocumentation.ps1`
- **Impact**: Finalizing a release via `prep-release` or `Update-ReleaseDocumentation -Finalize` inserted the new release section (`## [x.y.z]`) above `## [Unreleased]`, leaving an orphaned duplicate `## [Unreleased]` block in `CHANGELOG.md`.

---

## 1. Description

When preparing or finalizing a release from an active draft:

1. **Lingering Unreleased Section in `CHANGELOG.md`**:
   The existing `## [Unreleased]` heading was not replaced when generating the finalized version section `## [Version]`. Instead, `## [Version]` was inserted before `## [Unreleased]`, resulting in a duplicate unreleased block sitting below the newly finalized release notes.

2. **No-Version-Bump Protection**:
   When no version-bumping commits exist between the baseline tag and `HEAD`, attempting to finalize the same version throws:
   `Cannot finalize <Version> from <FromTag> because that version is already tagged.`
   The draft accurately remains under `## [Unreleased]` without creating corrupted or empty release entries.

---

## 2. Root Cause

1. **Regex Target Heading Match Failure**:
   In `Update-ReleaseDocumentation.ps1`, when finalizing (`$Finalize = $true`), `$headingMatch` sought `## [$Version]`. Since the version did not yet exist in `CHANGELOG.md`, the code stripped the managed markers from `## [Unreleased]` and inserted `## [$Version]` before the first `## [` match (which matched `## [Unreleased]`).

2. **`changelog.json` Version Array Contract**:
   When `CHANGELOG.md` had its `## [Unreleased]` heading finalized into a tagged version, the JSON catalog lost its `'unreleased'` version node unless explicitly preserved for future commits.

---

## 3. Resolution

1. **In-Place Section Promotion ([`scripts/Update-ReleaseDocumentation.ps1`](file:///home/sgkens/devspace/projects/web/_repo/staticcanvas/lume/rivet/scripts/Update-ReleaseDocumentation.ps1))**:
   When `$Finalize` is `$true` and `CHANGELOG.md` contains an active `## [Unreleased]` section:
   - Replaces `## [Unreleased]` in-place with `## [$Version]` + datestamp (`> YYYY-MM-DD`) + `$changelogBlock`.
   - Eliminates duplicate or lingering `## [Unreleased]` sections from the file.

2. **`changelog.json` Unreleased Node Preservation**:
   Ensures `docs/data/changelog.json` continuously maintains a clean `'unreleased'` version entry (`entries: []`, `included: 0`) after release finalization.

---

## 4. Verification

- Verified changelog generation with both draft updates and finalized releases.
- All **67 Pester tests** pass cleanly with 0 failures (`Invoke-Pester -Path ./tests/Rivet.Tests.ps1`).

