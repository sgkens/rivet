# Bug Report: Nested GitLab Project Path Is Parsed Incorrectly

- **Status**: Resolved
- **Date**: 2026-10-13
- **Component**: `scripts/Initialize-RivetRepository.ps1`
- **Impact**: Initializing `group/subgroup/project` assigns `subgroup` as the project name and generates incorrect metadata.

## Description

Repository initialization selects the second path segment instead of the final segment when parsing an origin URL. It also defaults repositories without a recognized origin to the organization-specific `staticcanvas` namespace.

## Required Resolution

- Preserve the complete remote project path.
- Select the final path segment as the project name.
- Use a neutral fallback namespace when no usable remote or package identity exists.
- Cover HTTPS and SSH-style nested paths with regression tests.

## Acceptance Criteria

- `https://gitlab.example/group/subgroup/project.git` resolves to project `project` and path `group/subgroup/project`.
- Repositories without a remote do not inherit a StaticCanvas identity.

## Resolution

Initialization now parses HTTPS and SSH-style remotes, preserves the complete namespace path, selects the final segment as the project name, derives the GitLab base URI from the remote host, and uses `local` when no identity is available. Existing JSON configuration remains authoritative on repeat runs.

## Verification

Regression coverage verifies nested self-hosted GitLab metadata and the neutral no-remote fallback; full suite: 88 passed, 0 failed.
