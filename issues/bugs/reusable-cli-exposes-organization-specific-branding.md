# Bug Report: Reusable CLI Exposes Organization-Specific Branding

- **Status**: Resolved
- **Date**: 2026-10-13
- **Component**: `scripts/Invoke-Rivet.ps1`, generic scaffold defaults
- **Impact**: Repositories outside the original organization are labelled as StaticCanvas projects and can receive organization-specific metadata.

## Description

The runtime banner identifies every consuming repository as a StaticCanvas repository. Generic scaffold defaults also include organization-specific package metadata.

## Required Resolution

- Brand the runtime as Rivet rather than the organization that created it.
- Keep Rivet's own module manifest attribution unchanged.
- Ensure generated repository files use inferred/configured project identity only.

## Acceptance Criteria

- No consuming-repository runtime path injects StaticCanvas branding.
- Rivet's own authorship and project URL remain intact.

## Resolution

The command banner now identifies Rivet itself, and generated package and repository URLs use inferred or configured project tokens rather than organization-specific values. Rivet's own module attribution was preserved.

## Verification

Banner and generic-scaffold hard-code regressions passed in the full 88-test suite.
