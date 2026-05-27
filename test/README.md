# Integration tests

## Layout

```text
test/
├── fixtures/          # ArgoCD Application manifests (test assets)
│   ├── home-assistant.yaml
│   ├── multiple-charts.yaml
│   └── oci-*.yaml
└── scripts/           # Test runners and expectations
    ├── run-integration-tests.sh
    └── integration-expectations.yaml
```

## Run locally

```bash
# Requires: node, yq, grep, helm, jq, crane (required for OCI fixtures; CI uses imjasonh/setup-crane)
bash test/scripts/run-integration-tests.sh
```

The runner streams updater output in real time (with color logs) and prints each expectation case as it runs.

Disable colored test output:

```bash
INTEGRATION_TEST_COLOR_LOGS=false bash test/scripts/run-integration-tests.sh
```

Show captured updater output after the run:

```bash
SHOW_INTEGRATION_OUTPUT=true bash test/scripts/run-integration-tests.sh
```

## Expectations

Edit `test/scripts/integration-expectations.yaml` to define what dry-run output should contain.

Each case supports:

| Field | Description |
| --- | --- |
| `name` | Human-readable test name |
| `match` | Regex that must appear at least once in updater output |
| `not_match` | Regex that must not appear |
| `count` | Minimum number of `match` occurrences (default: `1`) |

Use semver-style patterns (for example `[0-9]+\.[0-9]+\.[0-9]+`) instead of pinning exact versions so tests stay stable when registries publish new chart releases.

## Fixtures

| File | Purpose |
| --- | --- |
| `fixtures/home-assistant.yaml` | Traditional Helm repo (custom chart) |
| `fixtures/multiple-charts.yaml` | `spec.sources` with cert-manager + ingress-nginx |
| `fixtures/chart-with-values-ref.yaml` | Chart source + `ref: values` source |
| `fixtures/oci-*.yaml` | OCI sources (Docker Hub, GHCR, ECR, Quay, GCR) |
