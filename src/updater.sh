#!/bin/bash

set -o pipefail

main_directory="${INPUT_MAIN_DIRECTORY:-.}"
recursive="${INPUT_RECURSIVE:-true}"
color_logs="${INPUT_COLOR_LOGS:-true}"
dry_run="${INPUT_DRY_RUN:-false}"
updated_count=0

color_red="\033[1;31m"
color_green="\033[1;32m"
color_reset="\033[0m"

log_error() {
  local message="$1"
  if [ "$color_logs" = true ]; then
    echo -e "${color_red}${message}${color_reset}"
  else
    echo "$message"
  fi
}

log_success() {
  local message="$1"
  if [ "$color_logs" = true ]; then
    echo -e "${color_green}${message}${color_reset}"
  else
    echo "$message"
  fi
}

check_command() {
  command -v "$1" >/dev/null 2>&1 || {
    log_error "Error: The '$1' command is required but not installed. Please install the appropriate package."
    exit 1
  }
}

yq_patch_file() {
  local src_file="$1"
  local eval_line="$2"

  diff -B <(yq "$src_file") <(yq eval "$eval_line" "$src_file") | patch "$src_file"
}

check_command "helm"
check_command "jq"
check_command "yq"

is_empty_value() {
  local value="$1"
  [ -z "$value" ] || [ "$value" = "null" ]
}

is_oci_repo_url() {
  [[ "$1" == oci://* ]]
}

build_oci_reference() {
  local repo_url="$1"
  local chart="$2"
  local oci_ref="$repo_url"

  if ! is_empty_value "$chart"; then
    oci_ref="${repo_url%/}/${chart}"
  fi

  echo "$oci_ref"
}

select_latest_semver_tag() {
  grep -E '^v?[0-9]+\.[0-9]+\.[0-9]+$' | sed 's/^v//' | sort -V | tail -1
}

get_latest_oci_version() {
  local oci_ref="$1"
  local latest_version=""
  local helm_results

  helm_results=$(helm search repo "$oci_ref" --versions --output json 2>/dev/null || true)
  if [ -n "$helm_results" ] && echo "$helm_results" | jq -e 'type == "array" and length > 0' >/dev/null 2>&1; then
    latest_version=$(echo "$helm_results" | jq -r '.[].version' | select_latest_semver_tag)
  fi

  if is_empty_value "$latest_version"; then
    if ! command -v crane >/dev/null 2>&1; then
      log_error "Error: The 'crane' command is required for OCI chart sources. Install from https://github.com/google/go-containerregistry/tree/main/cmd/crane"
      echo ""
      return
    fi
    latest_version=$(crane ls "${oci_ref#oci://}" 2>/dev/null | select_latest_semver_tag)
  fi

  echo "$latest_version"
}

apply_target_revision_update() {
  local file="$1"
  local source_path="$2"
  local source_label="$3"
  local current_revision="$4"
  local latest_version="$5"

  if is_empty_value "$latest_version"; then
    log_error "Failed to retrieve the latest version for ${source_label} in $file."
    return 4
  fi

  if [ "$latest_version" = "$current_revision" ]; then
    log_success "No update needed for ${source_label} in $file ($current_revision)."
    return 2
  fi

  if [ "$dry_run" != true ]; then
    yq_patch_file "$file" "${source_path}.targetRevision = \"$latest_version\""
  fi

  log_success "Updated ${source_label} in $file to $latest_version."
  return 0
}

process_oci_chart_source() {
  local file="$1"
  local source_path="$2"
  local source_label="$3"

  local repo_url chart current_revision oci_ref latest_version
  repo_url=$(yq eval "${source_path}.repoURL" "$file")
  chart=$(yq eval "${source_path}.chart" "$file")
  current_revision=$(yq eval "${source_path}.targetRevision" "$file")

  if is_empty_value "$repo_url" || is_empty_value "$current_revision"; then
    return 3
  fi

  if ! is_oci_repo_url "$repo_url"; then
    return 3
  fi

  oci_ref=$(build_oci_reference "$repo_url" "$chart")
  latest_version=$(get_latest_oci_version "$oci_ref")
  apply_target_revision_update "$file" "$source_path" "$source_label" "$current_revision" "$latest_version"
}

process_helm_repo_chart_source() {
  local file="$1"
  local source_path="$2"
  local source_label="$3"
  local repo_alias="$4"

  local repo_url chart current_revision latest_version
  repo_url=$(yq eval "${source_path}.repoURL" "$file")
  chart=$(yq eval "${source_path}.chart" "$file")
  current_revision=$(yq eval "${source_path}.targetRevision" "$file")

  if is_empty_value "$repo_url" || is_empty_value "$chart" || is_empty_value "$current_revision"; then
    return 3
  fi

  if ! helm repo add "$repo_alias" "$repo_url" >/dev/null 2>&1; then
    helm repo remove "$repo_alias" >/dev/null 2>&1 || true
    if ! helm repo add "$repo_alias" "$repo_url" >/dev/null 2>&1; then
      log_error "Failed to add Helm repository '$repo_alias' from '$repo_url'. Skipping ${source_label}..."
      return 4
    fi
  fi

  if ! helm repo update "$repo_alias" >/dev/null 2>&1; then
    log_error "Failed to update Helm repository '$repo_alias'. Skipping ${source_label}..."
    return 4
  fi

  latest_version=$(helm search repo --regexp "\v$repo_alias/$chart\v" --versions --output json |
                    jq -r '.[0].version // empty')

  apply_target_revision_update "$file" "$source_path" "$source_label" "$current_revision" "$latest_version"
}

process_chart_source() {
  local file="$1"
  local source_path="$2"
  local source_label="$3"
  local repo_alias="$4"

  local repo_url
  repo_url=$(yq eval "${source_path}.repoURL" "$file")

  if is_oci_repo_url "$repo_url"; then
    process_oci_chart_source "$file" "$source_path" "$source_label"
    return $?
  fi

  process_helm_repo_chart_source "$file" "$source_path" "$source_label" "$repo_alias"
}

if [ "$recursive" = true ]; then
  find_command="find \"$main_directory\" -type f \( -name \"*.yaml\" -o -name \"*.yml\" \) -print0"
else
  find_command="find \"$main_directory\" -maxdepth 1 -type f \( -name \"*.yaml\" -o -name \"*.yml\" \) -print0"
fi

while IFS= read -r -d $'\0' file; do
  kind=$(yq eval '.kind' "$file")

  if [ "$kind" != "Application" ]; then
    continue
  fi

  app_name=$(yq eval ".metadata.name" "$file")
  if is_empty_value "$app_name"; then
    log_error "Missing .metadata.name in $file. Skipping..."
    continue
  fi

  file_updated=false
  compatible_source_found=false

  sources_count=$(yq eval '.spec.sources | length' "$file")
  if ! is_empty_value "$sources_count" && [ "$sources_count" -gt 0 ]; then
    for ((i = 0; i < sources_count; i++)); do
      source_path=".spec.sources[$i]"
      source_label="${source_path}"
      repo_alias="${app_name}-${i}"

      process_chart_source "$file" "$source_path" "$source_label" "$repo_alias"
      source_status=$?

      if [ "$source_status" -eq 0 ] || [ "$source_status" -eq 2 ]; then
        compatible_source_found=true
      fi

      if [ "$source_status" -eq 0 ]; then
        file_updated=true
      fi
    done
  else
    process_chart_source "$file" ".spec.source" ".spec.source" "$app_name"
    source_status=$?

    if [ "$source_status" -eq 0 ] || [ "$source_status" -eq 2 ]; then
      compatible_source_found=true
    fi

    if [ "$source_status" -eq 0 ]; then
      file_updated=true
    fi
  fi

  if [ "$compatible_source_found" != true ]; then
    log_error "No compatible Helm chart source found in $file. Skipping..."
    continue
  fi

  if [ "$file_updated" = true ]; then
    updated_count=$((updated_count + 1))
  fi
done < <(eval "$find_command")

if [ -n "${GITHUB_OUTPUT:-}" ]; then
  echo "updated_count=$updated_count" >> "$GITHUB_OUTPUT"
fi
