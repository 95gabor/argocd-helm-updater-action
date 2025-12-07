#!/bin/bash

# Integration test script for the updater
# This script tests the full updater functionality with test files

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
UPDATER_SCRIPT="$PROJECT_ROOT/src/updater.sh"

test_count=0
pass_count=0
fail_count=0

log_test() {
  local status="$1"
  local message="$2"
  test_count=$((test_count + 1))
  
  if [ "$status" = "pass" ]; then
    echo -e "${GREEN}✓${NC} Test $test_count: $message"
    pass_count=$((pass_count + 1))
  else
    echo -e "${RED}✗${NC} Test $test_count: $message"
    fail_count=$((fail_count + 1))
  fi
}

echo -e "${BLUE}Integration Tests for ArgoCD Helm Updater${NC}"
echo "=============================================="
echo ""

# Check if required commands are available
echo "Checking prerequisites..."
for cmd in helm yq jq; do
  if command -v "$cmd" >/dev/null 2>&1; then
    echo -e "  ${GREEN}✓${NC} $cmd is installed"
  else
    echo -e "  ${RED}✗${NC} $cmd is not installed"
    echo "  Please install $cmd to run tests"
    exit 1
  fi
done
echo ""

# Test 1: Script exists and is executable
if [ -f "$UPDATER_SCRIPT" ] && [ -x "$UPDATER_SCRIPT" ]; then
  log_test "pass" "Updater script exists and is executable"
else
  log_test "fail" "Updater script missing or not executable"
fi

# Test 2: Test files exist
echo ""
echo "Checking test files..."
for test_file in home-assistant.yaml oci-ghcr.yaml oci-docker.yaml oci-quay.yaml oci-gcr.yaml oci-azurecr.yaml oci-ecr.yaml; do
  if [ -f "$SCRIPT_DIR/$test_file" ]; then
    echo -e "  ${GREEN}✓${NC} $test_file exists"
  else
    echo -e "  ${RED}✗${NC} $test_file missing"
    log_test "fail" "Test file $test_file missing"
  fi
done

# Test 3: Validate YAML structure of test files
echo ""
echo "Validating YAML structure..."
for test_file in "$SCRIPT_DIR"/*.yaml; do
  if [ -f "$test_file" ]; then
    filename=$(basename "$test_file")
    if yq eval '.' "$test_file" >/dev/null 2>&1; then
      echo -e "  ${GREEN}✓${NC} $filename is valid YAML"
      
      # Check if it's an Application kind
      kind=$(yq eval '.kind' "$test_file" 2>/dev/null || echo "")
      if [ "$kind" = "Application" ]; then
        echo -e "    ${GREEN}✓${NC} Has Application kind"
        
        # Check required fields
        repo_url=$(yq eval '.spec.source.repoURL' "$test_file" 2>/dev/null || echo "")
        chart=$(yq eval '.spec.source.chart' "$test_file" 2>/dev/null || echo "")
        target_revision=$(yq eval '.spec.source.targetRevision' "$test_file" 2>/dev/null || echo "")
        app_name=$(yq eval '.metadata.name' "$test_file" 2>/dev/null || echo "")
        
        # For OCI charts, chart field is optional (chart name is in repoURL)
        # For traditional Helm repos, chart field is required
        is_oci=false
        # Match the actual OCI detection logic from updater.sh
        # Only detect OCI when explicitly marked with oci:// prefix
        if [[ "$repo_url" =~ ^oci:// ]]; then
          is_oci=true
        fi
        
        if [ -n "$repo_url" ] && [ -n "$target_revision" ] && [ -n "$app_name" ]; then
          if [ "$is_oci" = true ]; then
            # OCI charts don't require chart field
            log_test "pass" "$filename has all required fields (OCI format)"
          elif [ -n "$chart" ]; then
            # Traditional Helm repos require chart field
            log_test "pass" "$filename has all required fields"
          else
            log_test "fail" "$filename missing chart field (required for traditional Helm repos)"
          fi
        else
          log_test "fail" "$filename missing required fields"
        fi
      else
        log_test "fail" "$filename is not an Application kind"
      fi
    else
      log_test "fail" "$filename is not valid YAML"
    fi
  fi
done

# Test 4: Test dry-run mode (should not modify files)
echo ""
echo "Testing dry-run mode..."
TEMP_TEST_DIR=$(mktemp -d)
trap "rm -rf $TEMP_TEST_DIR" EXIT

cp "$SCRIPT_DIR/home-assistant.yaml" "$TEMP_TEST_DIR/"
original_content=$(cat "$TEMP_TEST_DIR/home-assistant.yaml")

export INPUT_MAIN_DIRECTORY="$TEMP_TEST_DIR"
export INPUT_RECURSIVE="false"
export INPUT_COLOR_LOGS="false"
export INPUT_DRY_RUN="true"

if bash "$UPDATER_SCRIPT" >/dev/null 2>&1; then
  new_content=$(cat "$TEMP_TEST_DIR/home-assistant.yaml")
  if [ "$original_content" = "$new_content" ]; then
    log_test "pass" "Dry-run mode does not modify files"
  else
    log_test "fail" "Dry-run mode modified files"
  fi
else
  log_test "fail" "Dry-run mode execution failed"
fi

# Test 5: Test OCI detection in test files
echo ""
echo "Testing OCI detection in test files..."
oci_files=("oci-ghcr.yaml" "oci-docker.yaml" "oci-quay.yaml" "oci-gcr.yaml" "oci-azurecr.yaml" "oci-ecr.yaml")
for oci_file in "${oci_files[@]}"; do
  if [ -f "$SCRIPT_DIR/$oci_file" ]; then
    repo_url=$(yq eval '.spec.source.repoURL' "$SCRIPT_DIR/$oci_file" 2>/dev/null || echo "")
    # Match the actual OCI detection logic from updater.sh
    # Only detect OCI when explicitly marked with oci:// prefix
    if [[ "$repo_url" =~ ^oci:// ]]; then
      log_test "pass" "$oci_file has OCI-compatible repoURL"
    else
      log_test "fail" "$oci_file does not appear to be OCI"
    fi
  fi
done

# Summary
echo ""
echo "=============================================="
echo "Test Summary:"
echo "  Total tests: $test_count"
echo -e "  ${GREEN}Passed: $pass_count${NC}"
if [ $fail_count -gt 0 ]; then
  echo -e "  ${RED}Failed: $fail_count${NC}"
  exit 1
else
  echo -e "  ${GREEN}Failed: $fail_count${NC}"
  echo ""
  echo -e "${GREEN}All tests passed!${NC}"
  exit 0
fi

