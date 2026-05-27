# Changelog

All notable changes to this project are documented in this file.

## v2.1.0 - 2026-05-27

### Features

- Added support for ArgoCD `spec.sources[]` and source-by-source chart update checks while keeping compatibility with `spec.source`.

## v2.0.0 - 2026-05-27

### Breaking Changes

- Action runtime updated from `node20` to `node24` in `action.yaml` (`runs.using`).
- Self-hosted runners must include a GitHub Actions runner version that supports Node.js 24-based JavaScript actions.

### Added

- New action output: `updated_count`.
- CI now includes ShellCheck for `src/updater.sh`.

### Changed

- Improved Helm repo handling to be more resilient across repeated runs.
- Improved chart version selection logic to use `helm search --versions` ordering.
- README usage examples now include `updated_count` output usage and corrected `main_directory` input name.
