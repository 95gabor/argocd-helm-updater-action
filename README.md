# ArgoCD Helm chart version updater GitHub Action

[![integration](https://github.com/95gabor/argocd-helm-updater-action/actions/workflows/integration.yaml/badge.svg?branch=main)](https://github.com/95gabor/argocd-helm-updater-action/actions/workflows/integration.yaml)
[![GitHub Marketplace](https://img.shields.io/badge/Marketplace-ArgoCD%20Helm%20updater-blue.svg?colorA=24292e&colorB=0366d6&style=flat&longCache=true&logo=github)](https://github.com/marketplace/actions/argocd-helm-chart-updater)

> See `CHANGELOG.md` for breaking changes and upgrade notes.

## Usage

### Minimal usage

```yaml
jobs:
  argo-update:
    name: Argo Helm chart version updater
    runs-on: ubuntu-22.04
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Simple test
        id: argo-update
        uses: 95gabor/argocd-helm-updater-action@v2

      - name: Show update count
        run: echo "Updated files: ${{ steps.argo-update.outputs.updated_count }}"
```

### Scheduled usage with automated PR

```yaml
name: ArgoCD Helm chart updater

on:
  workflow_dispatch:
  schedule:
    - cron: '0 0 * * 0'

jobs:
  build:
    permissions:
      contents: write
      pull-requests: write

    runs-on: ubuntu-22.04
    steps:
      - uses: actions/checkout@v4

      - uses: 95gabor/argocd-helm-updater-action@v2
        with:
          main_directory: ./infra
          recursive: true
          color_logs: true

      - name: Create Pull Request
        uses: peter-evans/create-pull-request@v5
        with:
          token: ${{ secrets.GITHUB_TOKEN }}
          title: 'bump(helm): update chart versions'
          body: 'Automatically updated Helm Chart versions'
          commit-message: 'build(helm): update chart versions'
          branch-suffix: timestamp
```

### OCI Helm charts

ArgoCD OCI sources are supported when `repoURL` uses the `oci://` prefix (for example `oci://registry-1.docker.io/bitnamicharts/nginx`).
The chart name can be part of `repoURL` (ArgoCD default) or provided via the optional `chart` field.

Version discovery uses `helm search` when available, then `crane ls` as a registry-agnostic fallback.
**`crane` is required** when `helm search` cannot list OCI chart versions (typical for most OCI registries).

**`crane` is not required** for traditional Helm repositories (`https://…` chart indexes).

For OCI chart sources, install [crane](https://github.com/google/go-containerregistry/tree/main/cmd/crane) on the runner. In GitHub Actions, use [imjasonh/setup-crane](https://github.com/imjasonh/setup-crane) before this action:

```yaml
- name: Setup crane
  uses: imjasonh/setup-crane@v0.5

- uses: 95gabor/argocd-helm-updater-action@v2
  with:
    main_directory: ./apps
```

Private registries work when credentials are configured (`helm registry login`, `crane auth login`, or Docker config used by `crane`).

Run integration tests locally with:

```bash
bash test/scripts/run-integration-tests.sh
```

Expectations are defined in `test/scripts/integration-expectations.yaml`. See `test/README.md` for details.

Integration test fixtures under `test/fixtures/` cover public OCI sources including:

- Docker Hub (`fixtures/oci-docker.yaml`) — Bitnami nginx
- GHCR (`fixtures/oci-ghcr.yaml`) — podinfo
- AWS Public ECR (`fixtures/oci-ecr.yaml`) — Karpenter
- Quay (`fixtures/oci-quay.yaml`) — Strimzi Kafka operator
- GCR (`fixtures/oci-gcr.yaml`) — Google microservices demo (public `gcr.io` OCI)
- 8gears Harbor (`fixtures/oci-8gears-n8n.yaml`) — [n8n](https://github.com/8gears/n8n-helm-chart) on `8gears.container-registry.com`

```yaml
# Docker Hub OCI (Bitnami nginx)
spec:
  source:
    repoURL: oci://registry-1.docker.io/bitnamicharts/nginx
    targetRevision: "15.9.0"
    path: .

# GitHub Container Registry OCI (podinfo)
# spec:
#   source:
#     repoURL: oci://ghcr.io/stefanprodan/charts/podinfo
#     targetRevision: "6.5.0"
#     path: .
```

## Action inputs

| Name | Description | Default Value |
| --- | --- | --- |
| `main_directory` | The directory where the script operates | `.` (current directory) |
| `recursive` | Perform updates recursively in subdirectories | `true` |
| `color_logs` | Enable colored logs for better visibility | `true` |
| `dry_run` | Simulate changes without modifying files | `false` |

## Action outputs

| Name | Description |
| --- | --- |
| `updated_count` | Number of ArgoCD Application files whose `targetRevision` was updated in this run |
