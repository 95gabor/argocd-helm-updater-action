# Changelog

All notable changes to this project are documented in this file.

## v2.2.0 - 2026-05-27

### Features

- Added OCI Helm chart support for ArgoCD Applications whose `repoURL` uses the `oci://` prefix.
- Works with both `spec.source` and `spec.sources[]` (non-chart sources such as `ref: values` are skipped).
- OCI version discovery uses `helm search` when available, then `crane ls`, with a Harbor API fallback for registries such as `8gears.container-registry.com`.
- Added public OCI integration fixtures (Docker Hub, GHCR, AWS Public ECR, Quay, GCR) and a YAML-driven integration test runner under `test/fixtures/` and `test/scripts/`.

### Optional setup: `crane` for OCI charts

No extra tooling is required for **traditional Helm repositories** (`https://…` chart indexes with a `chart` field). The action continues to work with `helm`, `yq`, and `jq` only.

If your Applications use **OCI chart sources** (`oci://…`), install [crane](https://github.com/google/go-containerregistry/tree/main/cmd/crane) in the workflow when `helm search` cannot list versions (common for most OCI registries).

In GitHub Actions, use [imjasonh/setup-crane](https://github.com/imjasonh/setup-crane) before this action (only when you have OCI chart sources):

```yaml
- name: Setup crane
  uses: imjasonh/setup-crane@v0.5

- uses: 95gabor/argocd-helm-updater-action@v2
  with:
    main_directory: ./apps
```

Private OCI registries use the same credentials as Helm/Docker (`helm registry login`, `crane auth login`, or `~/.docker/config.json` read by `crane`).

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
