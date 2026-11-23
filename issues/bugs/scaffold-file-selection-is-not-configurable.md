# Enhancement: Make Scaffold File Selection Configurable

- **Status**: Resolved
- **Date**: 2026-10-13
- **Component**: `scripts/Initialize-RivetRepository.ps1`, `repo_config.json`
- **Impact**: A repository can select a profile in JSON but cannot add or suppress scaffold files without editing executable profile code.

## Required Resolution

Add an optional `scaffold` configuration object that can exclude built-in destinations and append repository-local template mappings. Validate every configured source and destination as a repository-relative path.

## Acceptance Criteria

- Existing profiles remain backward compatible.
- `scaffold.exclude` suppresses named built-in destinations.
- `scaffold.templates` can add repository-local templates with token replacement.
- Absolute paths and parent-directory traversal are rejected.

## Resolution

All built-in profiles now expose `scaffold.exclude` and `scaffold.templates`. Repository-local mappings support token replacement and optional/mandatory behavior, with rooted and parent-traversal paths rejected before writes.

## Verification

Configuration-driven add/exclude behavior and config validation passed in the full 88-test suite.
