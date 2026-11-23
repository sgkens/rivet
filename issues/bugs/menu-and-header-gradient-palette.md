# Enhancement: Use Orange-to-Blue Menu and Header Gradients

- **Status**: Resolved
- **Date**: 2026-10-13
- **Component**: `scripts/smenu.ps1`, `scripts/Invoke-Rivet.ps1`
- **Impact**: Multi-action labels and the command header use inconsistent cyan/violet/magenta gradients.

## Required Resolution

- Render multi-action menu labels with one orange-to-blue gradient.
- Render the Rivet ASCII header with the same orange-to-blue endpoints.
- Preserve ANSI-aware layout calculations and atomic rendering.
- Update palette regression tests.

## Acceptance Criteria

- Both components start at RGB `255,130,0` and end at RGB `0,120,255`.
- Menu alignment tests remain green.

## Resolution

The multi-action menu title and Rivet ASCII header now share the requested RGB `255,130,0` to `0,120,255` gradient while retaining the ANSI-aware renderer.

## Verification

Palette and menu-layout regressions passed in the full 88-test suite.
