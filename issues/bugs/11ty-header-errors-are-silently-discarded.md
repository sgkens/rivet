# Bug Report: 11ty Header Errors Are Silently Discarded

- **Status**: Resolved
- **Date**: 2026-10-13
- **Component**: `profiles/11ty/profile.ps1`
- **Impact**: Invalid templates and metadata errors are hidden by a broad empty catch block, producing an unrelated fallback header instead of an actionable failure.

## Description

The 11ty profile catches every exception raised by the shared header renderer and discards it. This previously concealed an unresolved template token and can mask future configuration defects.

## Required Resolution

Invoke the shared renderer directly when its template exists and allow actionable failures to propagate. Retain the fallback only when the shared template itself is unavailable.

## Acceptance Criteria

- Renderer errors reach the caller.
- A missing optional shared template can still use the local fallback.
- Pester covers error propagation.

## Resolution

The 11ty profile now calls the shared header renderer without a broad catch. Its local fallback is used only when the shared template is unavailable.

## Verification

Covered by `propagates shared 11ty header rendering errors`; full suite: 88 passed, 0 failed.
