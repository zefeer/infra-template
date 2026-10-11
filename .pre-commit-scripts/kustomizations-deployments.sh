#!/bin/bash

# Exit immediately if a command exits with a non-zero status, treat unset variables as errors, and fail pipelines on the first error
set -euo pipefail

# Determine the root directory of the Git repository
BASE_DIR=$(git rev-parse --show-toplevel)
CLUSTERS_DIR="flux/clusters"

# Nothing staged under flux/ (deletions included, which pre-commit's files: filter can't see)
git -C "$BASE_DIR" diff --cached --quiet -- flux/ && exit 0

# Global/location/cluster _values directories merged into each app's values-<releaseName>
# ConfigMap, mirroring the _vars pattern in flux/clusters/internal/example-cluster/_vars.yaml.
# These are flux postBuild.substitute placeholders, not bash variables - keep single-quoted.
VALUES_COMPONENTS=(
  '../../${flux_git_path_to_root_from_clusters_dir}${flux_git_repo_path_base}/clusters/_values'
  '../../${flux_git_path_to_root_from_clusters_dir}${flux_git_repo_path_base}/clusters/${cluster_location}/_values'
  '../../${flux_git_path_to_root_from_clusters_dir}${flux_git_repo_path_base}/clusters/${cluster_location}/${cluster_name}/_values'
)

# ponytail: flux/base/_template/* kustomizations are hand-maintained (their resources are
# parent-relative, e.g. ../values.yaml) and are intentionally not touched by this script.

# Create a kustomization.yaml file with a default structure if it doesn't exist, or fill in
# any missing top-level fields if it does.
create_kustomization_file() {
  local dir="$1"
  local kustomization_file="$dir/kustomization.yaml"

  if [[ ! -f "$kustomization_file" ]]; then
    echo "Creating $kustomization_file"
    cat <<EOF > "$kustomization_file"
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources: []
replacements: []
EOF
    return
  fi

  echo "Updating missing fields in $kustomization_file if needed..."
  yq eval 'has("apiVersion")' "$kustomization_file" | grep -q true || yq eval '.apiVersion = "kustomize.config.k8s.io/v1beta1"' -i "$kustomization_file"
  yq eval 'has("kind")' "$kustomization_file" | grep -q true || yq eval '.kind = "Kustomization"' -i "$kustomization_file"
  yq eval 'has("resources")' "$kustomization_file" | grep -q true || yq eval '.resources = []' -i "$kustomization_file"
  yq eval 'has("replacements")' "$kustomization_file" | grep -q true || yq eval '.replacements = []' -i "$kustomization_file"
}

# Check if a file is already present in the resources list of kustomization.yaml
is_resource_listed() {
  local kustomization_file="$1"
  local file_name="$2"
  # ponytail: no `| grep -q` here - it closes the pipe early, yq gets SIGPIPE and pipefail flips the result randomly
  yq eval -e ".resources[] | select(. == \"$file_name\")" "$kustomization_file" >/dev/null 2>&1
}

# Remove a file from the resources list in kustomization.yaml
delete_from_resources() {
  local kustomization_file="$1"
  local file_name="$2"
  yq eval "del(.resources[] | select(. == \"$file_name\"))" "$kustomization_file" -i
}

# Check if a replacement rule already exists for the given Kustomization manifest
is_file_in_replacements() {
  local replacements_file="$1"
  local manifest_file="$2"
  local kustomization_name
  kustomization_name=$(yq eval ".metadata.name" "$manifest_file")
  yq eval -e ".[] | select(.source.name == \"$kustomization_name\")" "$replacements_file" >/dev/null 2>&1
}

is_flux_kustomization() {
  local file="$1"
  yq eval -e "select(.kind == \"Kustomization\" and .apiVersion | contains(\"kustomize.toolkit.fluxcd.io\"))" "$file" >/dev/null 2>&1
}

# Add tracked files in a cluster folder to kustomization.yaml as resources
add_resources() {
  local dir="$1"
  local relative_dir="${dir#"$BASE_DIR"/}"
  local kustomization_file="$dir/kustomization.yaml"

  create_kustomization_file "$dir"

  git -C "$BASE_DIR" ls-files "$dir" | while read -r file; do
    local relative_path="${file#"$relative_dir"/}"

    [[ "$relative_path" == *"/"* ]] && continue # skip files in subdirectories (_vars, _values, ...)
    [[ "$relative_path" =~ ^_replacements\.yaml(\.bak)?$ ]] && continue
    [[ "$relative_path" =~ ^kustomization\.yaml(\.bak)?$ ]] && continue

    if ! is_resource_listed "$kustomization_file" "$relative_path"; then
      echo "Adding $relative_path as a resource in $kustomization_file"
      yq eval ".resources += [\"$relative_path\"]" "$kustomization_file" -i
    fi
  done
  # Deduplicate resources list to avoid duplicates if the script is run multiple times
  yq eval '.resources |= unique' "$kustomization_file" -i
}

# Ensure an app Kustomization manifest's spec.components lists the _values directories
# for all three levels (global, location, cluster)
add_values_components() {
  local file="$1"
  local component
  for component in "${VALUES_COMPONENTS[@]}"; do
    if ! yq eval ".spec.components[] | select(. == \"$component\")" "$file" | grep -q .; then
      echo "Adding $component to spec.components in $file"
      yq eval ".spec.components += [\"$component\"]" -i "$file"
    fi
  done
}

# Generate replacement rules (in _replacements.yaml) for every app Kustomization manifest
# directly inside a cluster folder
add_replacements() {
  local dir="$1"
  local relative_dir="${dir#"$BASE_DIR"/}"
  local replacements_file="$dir/_replacements.yaml"

  git -C "$BASE_DIR" ls-files "$dir" | while read -r file; do
    local relative_path="${file#"$relative_dir"/}"

    # Skip subdirectory files, kustomization/replacements files, and underscore-prefixed
    # files (_vars.yaml etc. are not app Kustomizations and don't need a replacement rule)
    if [[ "$relative_path" == *"/"* || \
          "$relative_path" =~ ^(kustomization\.yaml|_replacements\.yaml)(\.bak)?$ || \
          "$relative_path" =~ ^_ ]]; then
      continue
    fi
    # Rules target patches that root injects into Flux Kustomizations only; anything else gets none
    is_flux_kustomization "$file" || continue
    if yq eval -e ".metadata.labels[] | select(. == \"skip_values\")" "$file" >/dev/null 2>&1; then
      echo "Skipping $relative_path (has skip_values label)"
      continue
    fi

    # add_values_components "$file"

    [[ -f "$replacements_file" ]] || echo "[]" > "$replacements_file"

    if ! is_file_in_replacements "$replacements_file" "$file"; then
      local kustomization_name
      kustomization_name=$(yq eval ".metadata.name" "$file")
      echo "Adding replacement rule for $kustomization_name in $replacements_file"
      local replacement_rule
      replacement_rule=$(cat <<EOF
- source:
    group: kustomize.toolkit.fluxcd.io
    kind: Kustomization
    fieldPath: metadata.name
    name: $kustomization_name
  targets:
    - fieldPaths:
        - spec.patches.[patch=.*Merge.*].target.name
      select:
        group: kustomize.toolkit.fluxcd.io
        kind: Kustomization
        name: $kustomization_name
      options:
        delimiter: '-'
        index: 1
EOF
)
      yq eval ". += (\"$replacement_rule\"|from_yaml)" "$replacements_file" -i
    fi
  done
  # Deduplicate replacement rules to avoid duplicates if the script is run multiple times
  yq eval 'unique_by(.source.name)' "$replacements_file" -i
}

# Reference _replacements.yaml from kustomization.yaml once it has at least one rule
add_replacements_to_kustomization() {
  local dir="$1"
  local kustomization_file="$dir/kustomization.yaml"
  local replacements_file="$dir/_replacements.yaml"

  [[ -f "$kustomization_file" ]] || return

  if [[ -f "$replacements_file" && "$(yq eval 'length' "$replacements_file")" -gt 0 ]]; then
    if ! yq eval -e '.replacements // [] | .[]' "$kustomization_file" >/dev/null 2>&1; then
      echo "Adding _replacements.yaml to $kustomization_file"
      yq eval '.replacements += {"path": "_replacements.yaml"}' -i "$kustomization_file"
    else
      echo "_replacements.yaml already present in $kustomization_file"
    fi
  fi
}

# Add components to kustomization.yaml for any _components/{kustomization_name} directories that contain a kustomization.yaml file
add_components_to_flux_kustomization() {
  local dir="$1"
  local kustomization_file="$dir/kustomization.yaml" 

  # Traverse up the hierarchy: current -> cluster -> location -> global
  local cluster_dir="${dir#"$BASE_DIR"/}"
  local location_dir=$(dirname "$cluster_dir")
  local global_dir=$(dirname "$location_dir")

  local tracked_files=$(git -C "$BASE_DIR" ls-files --exclude-standard --cached --modified -- $CLUSTERS_DIR)

  for file in $tracked_files; do

    [[ "$(basename "$file")" =~ ^_ ]] && continue # skip underscore-prefixed files (_vars, _values, _replacements etc.)
    if is_flux_kustomization "$file"; then
      local file_name=$(basename "$file" .yaml)

      if grep -qx "$global_dir/_components/$file_name/kustomization.yaml" <<< "$tracked_files"; then
        echo "Adding global _components to $file_name"
        yq eval ".spec.components += [\"../../\${flux_git_path_to_root_from_clusters_dir}\${flux_git_repo_path_base}/clusters/_components/$file_name\"]" "$file" -i
      else
        echo "Clean up global _components for $file_name"
        yq eval 'del(.spec.components[] | select(. == "../../${flux_git_path_to_root_from_clusters_dir}${flux_git_repo_path_base}/clusters/_components/$file_name"))' "$file" -i
      fi
      if grep -qx "$location_dir/_components/$file_name/kustomization.yaml" <<< "$tracked_files"; then
        echo "Adding location _components to $file_name"
        yq eval ".spec.components += [\"../../\${flux_git_path_to_root_from_clusters_dir}\${flux_git_repo_path_base}/clusters/\${cluster_location}/_components/$file_name\"]" "$file" -i
      else
        echo "Clean up location _components for $file_name"
        yq eval 'del(.spec.components[] | select(. == "../../${flux_git_path_to_root_from_clusters_dir}${flux_git_repo_path_base}/clusters/${cluster_location}/_components/$file_name"))' "$file" -i
      fi
      if grep -qx "$cluster_dir/_components/$file_name/kustomization.yaml" <<< "$tracked_files"; then
        echo "Adding cluster _components to $file_name"
        yq eval ".spec.components += [\"../../\${flux_git_path_to_root_from_clusters_dir}\${flux_git_repo_path_base}/clusters/\${cluster_location}/\${cluster_name}/_components/$file_name\"]" "$file" -i
      else
        echo "Clean up cluster _components for $file_name"
        yq eval 'del(.spec.components[] | select(. == "../../${flux_git_path_to_root_from_clusters_dir}${flux_git_repo_path_base}/clusters/${cluster_location}/${cluster_name}/_components/$file_name"))' "$file" -i
      fi
      # Deduplicate spec.components list to avoid duplicates
      yq eval '.spec.components |= unique' "$file" -i
    fi
  done

}

# Remove resources and replacement rules that no longer have a backing file
delete_non_existing() {
  local dir="$1"
  local relative_dir="${dir#"$BASE_DIR"/}"
  local kustomization_file="$dir/kustomization.yaml"
  local replacements_file="$dir/_replacements.yaml"

  local tracked_files
  tracked_files=$(git -C "$BASE_DIR" ls-files "$dir" | while read -r file; do
    local relative_path="${file#"$relative_dir"/}"
    [[ "$relative_path" == *"/"* ]] && continue
    [[ "$relative_path" =~ ^(kustomization\.yaml|_replacements\.yaml)(\.bak)?$ ]] && continue
    echo "$relative_path"
  done)

  yq eval '.resources[]' "$kustomization_file" | while read -r entry; do
    if ! grep -qx "$entry" <<< "$tracked_files"; then
      echo "Deleting non-existing resource $entry from $kustomization_file"
      delete_from_resources "$kustomization_file" "$entry"
    fi
  done

  [[ -f "$replacements_file" ]] || return 0

  yq eval '.[] | .source.name' "$replacements_file" | while read -r kustomization_name; do
    [[ "$kustomization_name" == "null" ]] && continue

    local exists=false
    while read -r f; do
      [[ -z "$f" ]] && continue
      if is_flux_kustomization "$dir/$f" && [[ "$(yq eval '.metadata.name' "$dir/$f" 2>/dev/null)" == "$kustomization_name" ]]; then
        exists=true
        break
      fi
    done <<< "$tracked_files"

    if [[ "$exists" == false ]]; then
      echo "Removing stale replacement rule for '$kustomization_name' from $replacements_file"
      yq eval "del(.[] | select(.source.name == \"$kustomization_name\"))" -i "$replacements_file"
    fi
  done
}

# Stage a file unless it's ignored by .gitignore
stage_file() {
  git -C "$BASE_DIR" ls-files --exclude-standard --cached --modified -- "$1" | while read -r f; do
    git -C "$BASE_DIR" add "$f"
  done
}

process_cluster_folders() {
  # Cluster folders are at depth 4: flux/clusters/<location>/<cluster>
  git -C "$BASE_DIR" ls-files -- "$CLUSTERS_DIR/" | xargs -n 1 dirname | sort -u | while read -r path; do
    [[ $(tr '/' '\n' <<< "$path" | wc -l) -eq 4 ]] || continue
    [[ "$(basename $(dirname "$path"))" =~ ^_ ]] && continue
    [[ "$(basename "$path")" =~ ^_ ]] && continue
    [[ -d "$BASE_DIR/$path" ]] || continue

    echo "Processing cluster folder: $path"
    local dir="$BASE_DIR/$path"
    add_resources "$dir"
    add_replacements "$dir"
    add_replacements_to_kustomization "$dir"
    add_components_to_flux_kustomization "$dir"
    delete_non_existing "$dir"

    stage_file "$path"
    # stage_file "$path/kustomization.yaml"
    # stage_file "$path/_replacements.yaml"
    # stage_file "$path/_components"
  done
}

process_cluster_folders
