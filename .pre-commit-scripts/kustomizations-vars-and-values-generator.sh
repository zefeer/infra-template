#!/bin/bash

# Exit immediately if a command exits with a non-zero status, treat unset variables as errors, and fail pipelines on the first error
set -euo pipefail

# Determine the root directory of the Git repository
BASE_DIR=$(git rev-parse --show-toplevel)
CLUSTERS_DIR="flux/clusters"

# Nothing staged under flux/ (deletions included, which pre-commit's files: filter can't see)
git -C "$BASE_DIR" diff --cached --quiet -- flux/ && exit 0

# Get the current level of the directory in the cluster hierarchy
get_current_level() {
  local dir="$1"
  local level=$(echo "${dir#$BASE_DIR/$CLUSTERS_DIR/}" | awk -F'/' '{print NF-1}') # Count the number of slashes to determine the level

  echo $level
}

# Create a kustomization.yaml file with a default structure if it doesn't exist in the given directory
create_kustomization_file() {
  local dir="$1"
  local kustomization_file="$dir/kustomization.yaml"
  local level
  level=$(get_current_level "$dir")

  local api_version="kustomize.config.k8s.io/v1beta1" kind="Kustomization"
  local label_fluxRole="$(basename "$dir")"

  [[ "$level" -gt 0 || "$(basename "$dir")" == "_values" ]] && api_version="kustomize.config.k8s.io/v1alpha1" kind="Component"

  if [[ ! -f "$kustomization_file" ]]; then
    echo "Creating $kustomization_file"
    cat <<EOF > "$kustomization_file"
apiVersion: $api_version
kind: $kind
resources: []
patches: []
generatorOptions:
  disableNameSuffixHash: true
  labels:
    flux-role: values-configMap
    # Run HelmRelease reconciliation, when configMap updates are detected, to ensure that the HelmRelease is reconciled with the latest values.
    reconcile.fluxcd.io/watch: Enabled
configMapGenerator: []
EOF
  fi

  api_version="$api_version" kind="$kind" label_fluxRole="${label_fluxRole#_}" yq eval '
    .apiVersion = env(api_version) |
    .kind = env(kind) |
    .resources = (.resources // []) |
    .patches = (.patches // []) |
    .generatorOptions = {"disableNameSuffixHash": true, "labels": {"flux-role": "$label_fluxRole-configMap" | envsubst, "reconcile.fluxcd.io/watch": "Enabled"}} | 
    .configMapGenerator = (.configMapGenerator // [])
  ' -i "$kustomization_file"
}

# Check if a file exists in a higher-level _vars or _values directory
check_upper_level_exists() {
  local current_dir="$1"
  local file_name="$2"

  # Traverse up the hierarchy: current -> cluster -> location -> global
  local cluster_dir=$(dirname "$current_dir")
  local location_dir=$(dirname "$cluster_dir")
  local global_dir=$(dirname "$location_dir")

  # Check if the file exists in the higher-level directories named the same as current_dir
  if [[ -f "$location_dir/$(basename "$current_dir")/$file_name" || -f "$global_dir/$(basename "$current_dir")/$file_name" ]]; then
    return 0
  fi
  return 1
}

# Compose a configMapGenerator name based on the directory level
compose_config_map_key() {
  local current_dir="$1"
  local level_count=$(get_current_level "$current_dir")
  local config_map_key=""

  for ((i=0; i<=level_count; i++)); do
    case $i in
      1) config_map_key="$config_map_key-\${cluster_location}" ;;
      2) config_map_key="$config_map_key-\${cluster_name}" ;;
    esac
  done

  echo "$config_map_key"
}

# Check if a file is already present in either the resources or patches section of the kustomization.yaml
is_file_in_kustomization() {
  local kustomization_file="$1"
  local file_name="$2"

  yq eval -e ".configMapGenerator.[].name | select(. == \"$file_name\")" "$kustomization_file" >/dev/null 2>&1
  # yq eval ".resources[] | contains(\"$file_name\")" "$kustomization_file" | grep --quiet 'true' || \
  # yq eval ".patches[].path | contains(\"$file_name\")" "$kustomization_file" | grep --quiet 'true'
}

# Remove duplicate entries from both resources and patches in the kustomization.yaml
check_for_doubles() {
  local dir="$1"
  local kustomization_file="$dir/kustomization.yaml"
  yq '.configMapGenerator |= unique_by(.name)' "$kustomization_file" -i
}

# Remove a file from the resources list in kustomization.yaml
delete_from_resources() {
  local dir="$1"
  local file_name="$2"
  local kustomization_file="$dir/kustomization.yaml"
  yq eval "del(.resources[] | select(. == \"$file_name\"))" "$kustomization_file" -i
}

# Remove a file from the patches list in kustomization.yaml
delete_from_patches() {
  local dir="$1"
  local file_name="$2"
  local kustomization_file="$dir/kustomization.yaml"
  yq eval "del(.patches[] | select(.path == \"$file_name\"))" "$kustomization_file" -i
}

# Remove a file from the configMapGenerator list in kustomization.yaml
delete_from_configmapgenerator() {
  local dir="$1"
  local file_name="$2"
  local kustomization_file="$dir/kustomization.yaml"
  yq eval "del(.configMapGenerator[] | select(.name == \"$file_name\"))" "$kustomization_file" -i
}

# Add tracked files to kustomization.yaml as resources or patches
add_files_to_kustomization() {
  local dir="$1"
  create_kustomization_file "$dir"
  local kustomization_file="$dir/kustomization.yaml"
  local behavior # Default behavior for configMapGenerator
  local file_list=""

  # Iterate over tracked or modified files only
  git ls-files --exclude-standard --cached --modified -- "$dir/*" | while read -r file; do
    [[ -f "$file" ]] || continue
    local file_name=$(basename "$file")
    local file_name_no_ext="${file_name%.*}"
    local file_name_no_prefix="${file_name_no_ext#*-}" # Remove prefix before the first dash, if any

    # Skip kustomization.yaml itself
    if [[ "$file_name" == "kustomization.yaml" || "$file_name" == "kustomization.yaml.bak" ]]; then
      continue
    fi

    if check_upper_level_exists "$dir" "$file_name"; then
      behavior="merge"
    else
      behavior="create"
    fi

    # Add to configMapGenerator if file exists
    if ! is_file_in_kustomization "$kustomization_file" "$file_name_no_ext"; then
      echo "basename $dir: $(basename "$dir")"
      if [[ "$(basename "$dir")" == "_values" ]]; then
        file_list="\"files\": [\"values$(compose_config_map_key "$dir").yaml=$file_name\"]"
      else
        file_list="\"envs\": [\"$file_name\"]"
      fi
      echo "Adding $file_name with behavior $behavior in $kustomization_file"
      yq eval ".configMapGenerator += {\"name\": \"${file_name_no_ext}\", \"behavior\": \"$behavior\", \"options\": {\"labels\": {\"flux-app\": \"${file_name_no_prefix}\"}}, $file_list}" "$kustomization_file" -i
    else
      echo "$file_name already exists in kustomization. Updateing behavior to $behavior if necessary."
      yq eval "(.configMapGenerator[] | select(.name == \"${file_name_no_ext}\").behavior) |= \"$behavior\"" "$kustomization_file" -i
    fi    
    
  done

  # Check for duplicates in configMapGenerator and remove them
  yq eval '.configMapGenerator |= unique_by(.name)' "$kustomization_file" -i
}

# Remove files from kustomization.yaml if they no longer exist in Git
delete_non_existing() {
  local dir="$1"
  local kustomization_file="$dir/kustomization.yaml"

  # Get relative path to match entries in kustomization.yaml
  local relative_dir="${dir#$BASE_DIR/}"
  local tracked_files
  tracked_files=$(git -C "$BASE_DIR" ls-files "$dir")

  # Remove missing entries
  yq eval '.configMapGenerator.[].name' "$kustomization_file" | while read -r entry; do
    if ! echo "$tracked_files" | grep -qx "$relative_dir/$entry.yaml"; then
      echo "Deleting non-existing resource $entry from $kustomization_file"
      delete_from_configmapgenerator "$dir" "${entry}" 
    fi
  done
}

# Process all _vars and _values directories in the cluster tree
process_vars_and_values() {
  local work_dir="$1"

  find "$work_dir" -type d \( -name "_vars" -o -name "_values" \) | sort -d | while read -r dir; do
    echo "Processing $dir"
    add_files_to_kustomization "$dir"
    check_for_doubles "$dir"
    delete_non_existing "$dir"
  done
}

# Start the processing from the clusters directory
process_vars_and_values "$BASE_DIR/$CLUSTERS_DIR/"

# Stage modified kustomization.yaml files unless ignored by .gitignore
echo "Staging kustomization.yaml files (excluding ignored ones)..."
git ls-files --exclude-standard --cached --modified -- 'flux/clusters/**/kustomization.yaml' | while read -r file; do
  echo "Staging $file"
  [[ -f "$file" ]] && git add "$file"
done
