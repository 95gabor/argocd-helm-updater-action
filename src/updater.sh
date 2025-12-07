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
check_command "curl"

if [ "$recursive" = true ]; then
  find_command="find \"$main_directory\" -type f \( -name \"*.yaml\" -o -name \"*.yml\" \) -print0"
else
  find_command="find \"$main_directory\" -maxdepth 1 -type f \( -name \"*.yaml\" -o -name \"*.yml\" \) -print0"
fi

eval "$find_command" | while IFS= read -r -d $'\0' file; do
  # Reset latest_version for each file to prevent stale values from previous iterations
  latest_version=""
  
  kind=$(yq eval '.kind' "$file")

  if [ "$kind" != "Application" ]; then
    continue
  fi

  repo_url=$(yq eval ".spec.source.repoURL" "$file")
  if [ -z "$repo_url" ]; then
    log_error "Missing .spec.source.repoURL in $file. Skipping..."
    continue
  fi

  chart=$(yq eval ".spec.source.chart" "$file" 2>/dev/null || echo "")
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

  # Detect if this is an OCI registry
  # Only detect OCI when explicitly marked with oci:// prefix to avoid misclassifying
  # traditional Helm repositories that might be hosted on container registry domains
  is_oci=false
  normalized_repo_url="$repo_url"
  
  if [[ "$repo_url" =~ ^oci:// ]]; then
    # Explicitly marked as OCI - this is the only safe way to detect OCI charts
    # Requiring explicit oci:// prefix prevents false positives for traditional Helm repos
    # that might be hosted on container registry domains (ghcr.io, docker.io, etc.)
    is_oci=true
    normalized_repo_url="$repo_url"
  fi

  if [ "$is_oci" = true ]; then
    # For OCI Helm charts, the chart name is part of the repoURL
    # According to ArgoCD docs: repoURL should be like oci://registry/chart-name
    # If a separate chart field exists, append it to the repoURL (for backward compatibility)
    # Check that chart is not empty and not the string "null" (yq returns "null" for missing/null fields)
    if [ -n "$chart" ] && [ "$chart" != "null" ]; then
      # Remove trailing slash from normalized_repo_url if present
      normalized_repo_url="${normalized_repo_url%/}"
      # Construct the full OCI URL: oci://registry/chart-name
      oci_url="${normalized_repo_url}/${chart}"
    else
      # Chart name is already in the repoURL (ArgoCD standard format)
      oci_url="$normalized_repo_url"
    fi
    
    # Discover latest OCI chart version by querying registry API for available tags
    # Extract registry and repository from OCI URL (e.g., oci://registry-1.docker.io/bitnamicharts/nginx)
    oci_url_no_prefix="${oci_url#oci://}"
    registry_domain=$(echo "$oci_url_no_prefix" | cut -d'/' -f1)
    repository_path=$(echo "$oci_url_no_prefix" | cut -d'/' -f2-)
    
    # Normalize registry domains for API access
    api_registry="$registry_domain"
    api_repository="$repository_path"
    if [ "$registry_domain" = "registry-1.docker.io" ] || [ "$registry_domain" = "docker.io" ]; then
      api_registry="registry-1.docker.io"
      # Docker Hub: repository path is used as-is (e.g., bitnamicharts/nginx)
      # Only official images use library/ prefix, which is already in the path if needed
      api_repository="$repository_path"
    elif [ "$registry_domain" = "ghcr.io" ]; then
      api_registry="ghcr.io"
      api_repository="$repository_path"
    elif [ "$registry_domain" = "gcr.io" ] || [[ "$registry_domain" =~ ^[^/]+\.gcr\.io$ ]]; then
      api_registry="$registry_domain"
      api_repository="$repository_path"
    elif [[ "$registry_domain" =~ \.azurecr\.io$ ]]; then
      api_registry="$registry_domain"
      api_repository="$repository_path"
    elif [[ "$registry_domain" =~ \.ecr\.[^/]+\.amazonaws\.com$ ]]; then
      api_registry="$registry_domain"
      api_repository="$repository_path"
    elif [ "$registry_domain" = "quay.io" ]; then
      api_registry="quay.io"
      api_repository="$repository_path"
    else
      # Generic OCI registry
      api_registry="$registry_domain"
      api_repository="$repository_path"
    fi
    
    # Query Docker Registry API v2 to list tags
    # Standard OCI registries use Docker Registry API v2
    tags_json=""
    
    # Construct API URL for tags list endpoint (Docker Registry API v2)
    tags_url="https://$api_registry/v2/$api_repository/tags/list"
    tags_response=$(curl -sL "$tags_url" 2>/dev/null)
    
    # Check if response contains tags (may require authentication for private repos)
    if echo "$tags_response" | jq -e '.tags' >/dev/null 2>&1; then
      tags_json=$(echo "$tags_response" | jq -r '.tags[]' 2>/dev/null || echo "")
    elif echo "$tags_response" | jq -e '.errors' >/dev/null 2>&1; then
      # API returned an error (may be authentication required or repository not found)
      error_msg=$(echo "$tags_response" | jq -r '.errors[0].message' 2>/dev/null || echo "Unknown error")
      log_error "Registry API error for $oci_url: $error_msg"
    fi
    
    # Filter tags for semantic versions and find latest
    if [ -n "$tags_json" ]; then
      # Filter for semantic version tags (e.g., 1.2.3, v1.2.3, 1.2.3-beta.1)
      # Exclude non-version tags like 'latest', 'main', 'dev', etc.
      # tags_json is already a newline-separated list from jq
      semver_tags=$(echo "$tags_json" | grep -E '^v?[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?(\+[0-9A-Za-z-]+)?$' | sort -V | tail -1)
      
      if [ -n "$semver_tags" ]; then
        # Remove 'v' prefix if present for consistency
        latest_version=$(echo "$semver_tags" | sed 's/^v//')
      fi
    fi
    
    # Fallback: If API query failed, try using helm to discover versions
    # This is limited but may work for some registries
    if [ -z "$latest_version" ]; then
      # Try to use helm search/version constraints (limited support)
      # Some registries may support version ranges
      if [ -n "$current_revision" ]; then
        # Validate current version is accessible
        chart_info=$(helm show chart "$oci_url" --version "$current_revision" 2>/dev/null)
        if [ -n "$chart_info" ]; then
          version_from_yq=$(echo "$chart_info" | yq eval '.version' - 2>/dev/null)
          if [ -n "$version_from_yq" ] && [ "$version_from_yq" != "null" ]; then
            # Use current version as fallback if we can't discover newer ones
            latest_version="$version_from_yq"
          fi
        fi
      fi
    fi
    
    # Log warning if we couldn't discover versions via API
    if [ -z "$latest_version" ]; then
      log_error "Could not discover latest version for OCI chart $oci_url. Registry API access may be required for private repositories, or the repository may not have semantic version tags."
    fi
  else
    # Traditional Helm repository - chart field is required
    # Check that chart is not empty and not the string "null" (yq returns "null" for missing/null fields)
    if [ -z "$chart" ] || [ "$chart" = "null" ]; then
      log_error "Missing chart in $file. Skipping..."
      continue
    fi
    
    helm repo add "$app_name" "$repo_url"
    helm repo update "$app_name"

    # Use helm search with output as json and jq to filter the result
    latest_version=$(helm search repo --regexp "\v$app_name/$chart\v" --output json | 
                      jq -r "max_by(.version) | .version // empty")
  fi

  if [ -n "${latest_version}" ]; then
    if [ "$dry_run" != true ]; then
      yq_patch_file "$file" ".spec.source.targetRevision = \"$latest_version\""
    fi
    log_success "Updated targetRevision in $file to $latest_version."
  else
    log_error "Failed to retrieve the latest version of the Helm Chart for $file."
  fi
done
