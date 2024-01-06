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

## Action inputs

| Name | Description | Default Value |
| --- | --- | --- |
| `main_directory` | The directory where the script operates | `.` (current directory) |
| `recursive` | Perform updates recursively in subdirectories | `true` |
| `color_logs` | Enable colored logs for better visibility | `true` |
| `dry_run` | Simulate changes without modifying files | `false` |
