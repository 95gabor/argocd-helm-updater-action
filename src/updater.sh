#!/bin/bash

main_directory="${INPUT_MAIN_DIRECTORY:-.}"
recursive="${INPUT_RECURSIVE:-true}"
color_logs="${INPUT_COLOR_LOGS:-true}"
dry_run="${INPUT_DRY_RUN:-false}"

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

if [ "$recursive" = true ]; then
  find_command="find \"$main_directory\" -type f \( -name \"*.yaml\" -o -name \"*.yml\" \) -print0"
else
  find_command="find \"$main_directory\" -maxdepth 1 -type f \( -name \"*.yaml\" -o -name \"*.yml\" \) -print0"
fi

eval "$find_command" | while IFS= read -r -d $'\0' file; do
  kind=$(yq eval '.kind' "$file")

  if [ "$kind" != "Application" ]; then
    continue
  fi

  repo_url=$(yq eval ".spec.source.repoURL" "$file")
  if [ -z "$repo_url" ]; then
    log_error "Missing .spec.source.repoURL in $file. Skipping..."
    continue
  fi

  chart=$(yq eval ".spec.source.chart" "$file")
  if [ -z "$chart" ]; then
    log_error "Missing chart in $file. Skipping..."
    continue
  fi

  current_revision=$(yq eval ".spec.source.targetRevision" "$file")
  if [ -z "$current_revision" ]; then
    log_error "Missing .spec.source.targetRevision in $file. Skipping..."
    continue
  fi

  app_name=$(yq eval ".metadata.name" "$file")
  if [ -z "$app_name" ]; then
    log_error "Missing .metadata.name in $file. Skipping..."
    continue
  fi

  helm repo add "$app_name" "$repo_url"
  helm repo update "$app_name"

  # Use helm search with output as json and jq to filter the result
  latest_version=$(helm search repo --regexp "\v$app_name/$chart\v" --output json | 
                    jq -r "max_by(.version) | .version // empty")

  if [ -n "${latest_version}" ]; then
    if [ "$dry_run" != true ]; then
      yq_patch_file "$file" ".spec.source.targetRevision = \"$latest_version\""
    fi
    log_success "Updated targetRevision in $file to $latest_version."
  else
    log_error "Failed to retrieve the latest version of the Helm Chart for $file."
  fi
done
