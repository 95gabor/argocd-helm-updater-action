# Test Suite

This directory contains test files and test scripts for the ArgoCD Helm Updater Action.

## Test Files

### Traditional Helm Repository Tests
- `home-assistant.yaml` - Example ArgoCD Application using a traditional Helm repository

### OCI Registry Tests
- `oci-ghcr.yaml` - GitHub Container Registry (ghcr.io) with explicit `oci://` prefix
- `oci-docker.yaml` - Docker Hub (docker.io) with HTTPS URL
- `oci-quay.yaml` - Quay.io registry
- `oci-gcr.yaml` - Google Container Registry (gcr.io)
- `oci-azurecr.yaml` - Azure Container Registry (azurecr.io)
- `oci-ecr.yaml` - AWS Elastic Container Registry (ECR)

## Test Scripts

### `test-oci-detection.sh`
Unit tests for OCI registry detection logic. Tests various URL formats to ensure correct detection of OCI registries vs traditional Helm repositories.

**Usage:**
```bash
./test/test-oci-detection.sh
```

**What it tests:**
- Explicit `oci://` prefix detection
- Known container registry domain detection (ghcr.io, docker.io, quay.io, gcr.io, azurecr.io, ECR)
- Traditional Helm repo URLs should NOT be detected as OCI
- Edge cases (http vs https, localhost, file protocol, etc.)

### `test-script.sh`
Integration tests for the full updater functionality.

**Usage:**
```bash
./test/test-script.sh
```

**What it tests:**
- Script exists and is executable
- Test files exist and are valid YAML
- Test files have required ArgoCD Application fields
- Dry-run mode doesn't modify files
- OCI detection works correctly in test files

## Running Tests Locally

### Prerequisites
- `helm` - Helm CLI tool
- `yq` - YAML processor
- `jq` - JSON processor
- `bash` - Shell interpreter

### Run All Tests
```bash
# Make scripts executable (if not already)
chmod +x test/*.sh

# Run OCI detection tests
./test/test-oci-detection.sh

# Run integration tests
./test/test-script.sh
```

### Test with the Action (Dry Run)
```bash
# Test with dry-run mode (won't modify files)
export INPUT_MAIN_DIRECTORY=./test
export INPUT_RECURSIVE=true
export INPUT_DRY_RUN=true
export INPUT_COLOR_LOGS=false

./src/updater.sh
```

## CI/CD Integration

Tests are automatically run in GitHub Actions via the `.github/workflows/integration.yaml` workflow:

- **OCI detection tests** - Validates OCI registry detection logic
- **Integration tests** - Validates full functionality
- **Dry-run tests** - Tests the action with OCI files in dry-run mode

The workflow runs on:
- Pull requests that modify source code, tests, or workflows
- Pushes to the main branch

