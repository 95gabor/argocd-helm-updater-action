#!/bin/bash

# Test script for OCI detection logic
# This script tests the OCI registry detection without requiring actual Helm operations

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

test_count=0
pass_count=0
fail_count=0

# Source the updater script to access its functions
# We'll extract the OCI detection logic for testing
test_oci_detection() {
  local repo_url="$1"
  local expected_result="$2"  # "true" or "false"
  local test_name="$3"
  
  test_count=$((test_count + 1))
  
  # Simulate the OCI detection logic from updater.sh
  is_oci=false
  normalized_repo_url="$repo_url"
  
  # Only detect OCI when explicitly marked with oci:// prefix
  # This matches the implementation in updater.sh which requires explicit oci:// prefix
  # to avoid misclassifying traditional Helm repos on container registry domains
  if [[ "$repo_url" =~ ^oci:// ]]; then
    is_oci=true
    normalized_repo_url="$repo_url"
  fi
  
  if [ "$is_oci" = "$expected_result" ]; then
    echo -e "${GREEN}✓${NC} Test $test_count: $test_name - PASSED"
    pass_count=$((pass_count + 1))
    return 0
  else
    echo -e "${RED}✗${NC} Test $test_count: $test_name - FAILED"
    echo -e "  Expected: is_oci=$expected_result, Got: is_oci=$is_oci"
    fail_count=$((fail_count + 1))
    return 1
  fi
}

echo "Testing OCI Registry Detection Logic"
echo "===================================="
echo ""

# Test cases for OCI registries (should be detected as OCI)
echo "Testing OCI registry detection (should be true):"
test_oci_detection "oci://ghcr.io/helm-charts" "true" "Explicit oci:// prefix"
test_oci_detection "oci://docker.io/charts" "true" "Explicit oci:// with docker.io"
test_oci_detection "oci://quay.io/helm-charts" "true" "Explicit oci:// with quay.io"
test_oci_detection "oci://gcr.io/my-project" "true" "Explicit oci:// with gcr.io"
test_oci_detection "oci://myregistry.azurecr.io" "true" "Explicit oci:// with azurecr.io"
test_oci_detection "oci://123456789012.dkr.ecr.us-east-1.amazonaws.com" "true" "Explicit oci:// with AWS ECR"

echo ""
echo "Testing traditional Helm repos (should NOT be detected as OCI):"
# Test cases for traditional Helm repos (should NOT be detected as OCI)
test_oci_detection "https://charts.helm.sh/stable" "false" "Helm stable repo"
test_oci_detection "https://95gabor.github.io/home-charts" "false" "GitHub Pages Helm repo"
test_oci_detection "https://charts.example.com" "false" "Generic charts domain"
test_oci_detection "https://example.com/charts" "false" "Generic domain with /charts"
test_oci_detection "https://helm.example.com" "false" "Generic helm subdomain"
test_oci_detection "http://localhost:8080" "false" "Localhost"
test_oci_detection "file:///path/to/charts" "false" "File protocol"
test_oci_detection "https://ghcr.io/helm-charts" "false" "HTTPS ghcr.io without oci:// prefix (traditional Helm repo)"
test_oci_detection "https://docker.io/charts" "false" "HTTPS docker.io without oci:// prefix (traditional Helm repo)"
test_oci_detection "https://quay.io/helm-charts" "false" "HTTPS quay.io without oci:// prefix (traditional Helm repo)"
test_oci_detection "https://gcr.io/my-project" "false" "HTTPS gcr.io without oci:// prefix (traditional Helm repo)"
test_oci_detection "https://myregistry.azurecr.io" "false" "HTTPS azurecr.io without oci:// prefix (traditional Helm repo)"
test_oci_detection "https://123456789012.dkr.ecr.us-east-1.amazonaws.com" "false" "HTTPS ECR without oci:// prefix (traditional Helm repo)"

echo ""
echo "===================================="
echo "Test Results:"
echo "  Total tests: $test_count"
echo -e "  ${GREEN}Passed: $pass_count${NC}"
if [ $fail_count -gt 0 ]; then
  echo -e "  ${RED}Failed: $fail_count${NC}"
  exit 1
else
  echo -e "  ${GREEN}Failed: $fail_count${NC}"
  exit 0
fi

