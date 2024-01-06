# ArgoCD Helm chart version updater GitHub Action

## Usage

```yaml
jobs:
  argo-update:
    name: Argo Helm chart version updater
    runs-on: ubuntu-22.04
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Simple test
        uses: 95gabor/argocd-helm-updater
        with:
          main_director: ./infra
```
