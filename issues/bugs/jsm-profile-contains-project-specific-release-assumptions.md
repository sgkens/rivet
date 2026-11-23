# Bug Report: Generic JSM Profile Contains Project-Specific Release Assumptions

- **Status**: Resolved
- **Date**: 2026-10-13
- **Component**: `templates/js/`, `profiles/jsm/profile.ps1`
- **Impact**: Repositories scaffolded with the generic JavaScript profile can fail builds and release validation unless they use Lume, Asciiam, Logcad, Hugo, and the original repository layout.

## Description

The reusable JSM profile contains package exports, build modes, documentation paths, release checks, dependencies, CI services, and retained scripts copied from individual StaticCanvas projects.

## Required Resolution

- Reduce the default JavaScript package and Vite configuration to a neutral library baseline.
- Drive optional release checks from `repo_config.json`.
- Replace organization-specific CI with a portable Node pipeline.
- Remove unused project-specific template scripts.
- Add regression tests that reject known project-specific identifiers in the generic scaffold.

## Acceptance Criteria

- A newly scaffolded JSM repository has no Lume, Asciiam, Logcad, Hugo, StaticCanvas, or Phellams runtime requirement.
- Release validation derives bundle requirements from package metadata and optional repository configuration.
- The default build does not require documentation, branding, optional diagnostic entry points, or private infrastructure.

## Resolution

The JSM scaffold now supplies a neutral Vite library build and portable Node CI. Bundle and release checks read optional limits and file rules from `repo_config.json`; obsolete project-specific scripts, exports, dependencies, and lockfile templates were removed. JSR integration is optional.

## Verification

JavaScript syntax and JSON template parsing passed. A regression scan rejects known project-specific identifiers from the generic scaffold; full suite: 88 passed, 0 failed.
