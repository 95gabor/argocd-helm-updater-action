# ArgoCD Helm chart version updater GitHub Action
[![integration](https://github.com/95gabor/argocd-helm-updater-action/actions/workflows/integration.yaml/badge.svg?branch=main)](https://github.com/95gabor/argocd-helm-updater-action/actions/workflows/integration.yaml)
[![GitHub Marketplace](https://img.shields.io/badge/Marketplace-ArgoCD%20Helm%20updater-blue.svg?colorA=24292e&colorB=0366d6&style=flat&longCache=true&logo=github)](https://github.com/marketplace/actions/argocd-helm-chart-updater)

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
        uses: 95gabor/argocd-helm-updater-action@v1
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

      - uses: 95gabor/argocd-helm-updater-action@v1
        with:
          main_director: ./infra
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

## OCI Registry Support

This action supports both traditional Helm repositories and OCI (Open Container Initiative) registries. OCI registries are detected when:

- The `repoURL` starts with `oci://` prefix (required for OCI detection)

**Note:** The `oci://` prefix is required to distinguish OCI Helm charts from traditional Helm repositories. This prevents misclassification of traditional Helm repos that might be hosted on container registry domains.

For OCI registries, the action uses Helm's native OCI support (requires Helm 3.8+) to discover and update chart versions.

According to [ArgoCD OCI documentation](https://argo-cd.readthedocs.io/en/latest/user-guide/oci/), for OCI Helm charts:
- The chart name is part of the `repoURL` (e.g., `oci://registry-1.docker.io/bitnamicharts/nginx`)
- The `chart` field is **not used** - the chart name is included in the URL path
- The `path` field should be set to `.` for OCI Helm charts
- The `targetRevision` specifies the chart version/tag

### Example OCI Configuration

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: nginx
spec:
  source:
    repoURL: oci://registry-1.docker.io/bitnamicharts/nginx
    targetRevision: 15.9.0
    path: .
  destination:
    server: https://kubernetes.default.svc
    namespace: nginx
```

**Note:** OCI registries require explicit semantic version tags. The action automatically discovers the latest version by querying the registry API (Docker Registry API v2) to list available tags, then filters for semantic versions and selects the latest stable release. For private repositories, authentication may be required. The action supports common registries including Docker Hub, GHCR, GCR, Quay.io, Azure ACR, and AWS ECR.

## Action inputs

| Name | Description | Default Value |
| --- | --- | --- |
| `main_directory` | The directory where the script operates | `.` (current directory) |
| `recursive` | Perform updates recursively in subdirectories | `true` |
| `color_logs` | Enable colored logs for better visibility | `true` |
| `dry_run` | Simulate changes without modifying files | `false` |
