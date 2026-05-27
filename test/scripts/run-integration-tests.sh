#!/bin/bash

# Run the updater in dry-run mode and validate stdout against integration-expectations.yaml.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
EXPECTATIONS_FILE="${ROOT_DIR}/test/scripts/integration-expectations.yaml"
FIXTURES_DIR="${ROOT_DIR}/test/fixtures"
OUTPUT_FILE="$(mktemp)"

COLOR_LOGS="${INTEGRATION_TEST_COLOR_LOGS:-true}"

color_red="\033[1;31m"
color_green="\033[1;32m"
color_yellow="\033[1;33m"
color_blue="\033[1;34m"
color_reset="\033[0m"

pass_count=0
fail_count=0
case_count=0

log_info() {
  local message="$1"
  if [ "$COLOR_LOGS" = true ]; then
    echo -e "${color_blue}${message}${color_reset}"
  else
    echo "$message"
  fi
}

log_success() {
  local message="$1"
  if [ "$COLOR_LOGS" = true ]; then
    echo -e "${color_green}${message}${color_reset}"
  else
    echo "$message"
  fi
}

log_warning() {
  local message="$1"
  if [ "$COLOR_LOGS" = true ]; then
    echo -e "${color_yellow}${message}${color_reset}"
  else
    echo "$message"
  fi
}

log_error() {
  local message="$1"
  if [ "$COLOR_LOGS" = true ]; then
    echo -e "${color_red}${message}${color_reset}" >&2
  else
    echo "$message" >&2
  fi
}

require_command() {
  local command_name="$1"
  if command -v "$command_name" >/dev/null 2>&1; then
    log_success "  ✓ found: $command_name"
    return 0
  fi

  log_error "  ✗ missing required command: $command_name"
  return 1
}

strip_ansi() {
  sed -E 's/\x1B\[[0-9;]*m//g'
}

count_matches() {
  local pattern="$1"
  grep -Ec "$pattern" "$OUTPUT_FILE" || true
}

run_expectation() {
  local index="$1"
  local name="$2"
  local match="${3:-}"
  local not_match="${4:-}"
  local expected_count="${5:-1}"

  log_info ""
  log_info "[$index/$case_count] $name"

  if [ -z "$match" ] && [ -z "$not_match" ]; then
    log_error "  Invalid expectation: set match and/or not_match"
    fail_count=$((fail_count + 1))
    return 1
  fi

  if [ -n "$match" ]; then
    log_info "  Checking match (>= $expected_count): $match"
    local count
    count=$(count_matches "$match")
    if [ "$count" -lt "$expected_count" ]; then
      log_error "  FAIL: expected at least $expected_count match(es), got $count"
      fail_count=$((fail_count + 1))
      return 1
    fi
    log_success "  PASS: match found ($count occurrence(s))"
  fi

  if [ -n "$not_match" ]; then
    log_warning "  Checking not_match: $not_match"
    local forbidden_count
    forbidden_count=$(count_matches "$not_match")
    if [ "$forbidden_count" -gt 0 ]; then
      log_error "  FAIL: unexpected match ($forbidden_count occurrence(s))"
      fail_count=$((fail_count + 1))
      return 1
    fi
    log_success "  PASS: forbidden pattern not found"
  fi

  log_success "  ✓ case passed: $name"
  pass_count=$((pass_count + 1))
}

missing_commands=0
log_info "Checking required commands ..."
for command_name in yq node grep helm jq crane; do
  require_command "$command_name" || missing_commands=$((missing_commands + 1))
done

if [ "$missing_commands" -gt 0 ]; then
  log_error "Install missing commands before running integration tests."
  exit 1
fi

if [ ! -f "$EXPECTATIONS_FILE" ]; then
  log_error "Expectations file not found: $EXPECTATIONS_FILE"
  exit 1
fi

if [ ! -d "$FIXTURES_DIR" ]; then
  log_error "Fixtures directory not found: $FIXTURES_DIR"
  exit 1
fi

case_count=$(yq '.cases | length' "$EXPECTATIONS_FILE")
log_info ""
log_info "Loaded $case_count expectation case(s) from integration-expectations.yaml"
log_info ""
log_info "Running updater (dry-run, color logs) against ./test/fixtures ..."
log_info "────────────────────────────────────────────────────────"

set +e
(
  cd "$ROOT_DIR"
  INPUT_MAIN_DIRECTORY=./test/fixtures \
  INPUT_RECURSIVE=true \
  INPUT_COLOR_LOGS=true \
  INPUT_DRY_RUN=true \
  node src/index.js
) 2>&1 | tee >(strip_ansi >"$OUTPUT_FILE")
updater_exit_code="${PIPESTATUS[0]}"
set -e

log_info "────────────────────────────────────────────────────────"

if [ "$updater_exit_code" -ne 0 ]; then
  log_error "Updater exited with code $updater_exit_code"
  rm -f "$OUTPUT_FILE"
  exit 1
fi

log_success "Updater finished successfully"
log_info ""
log_info "Validating expectations against captured output ..."
log_info "=========================================================="

for ((i = 0; i < case_count; i++)); do
  name=$(yq -r ".cases[$i].name" "$EXPECTATIONS_FILE")
  match=$(yq -r ".cases[$i].match // \"\"" "$EXPECTATIONS_FILE")
  not_match=$(yq -r ".cases[$i].not_match // \"\"" "$EXPECTATIONS_FILE")
  expected_count=$(yq -r ".cases[$i].count // 1" "$EXPECTATIONS_FILE")

  if [ "$match" = "null" ]; then
    match=""
  fi
  if [ "$not_match" = "null" ]; then
    not_match=""
  fi

  run_expectation "$((i + 1))" "$name" "$match" "$not_match" "$expected_count" || true
done

log_info ""
log_info "=========================================================="
if [ "$fail_count" -eq 0 ]; then
  log_success "All integration tests passed ($pass_count/$case_count)"
else
  log_error "Integration tests failed: $fail_count failed, $pass_count passed (total $case_count)"
fi

if [ "${SHOW_INTEGRATION_OUTPUT:-}" = "true" ]; then
  log_info ""
  log_info "Captured updater output (ANSI stripped):"
  cat "$OUTPUT_FILE"
fi

rm -f "$OUTPUT_FILE"

if [ "$fail_count" -gt 0 ]; then
  exit 1
fi
