#!/usr/bin/env bash
#
# kubeconform.sh - validate rendered manifests against Kubernetes and CRD schemas.
#
# Custom resources are validated against the CRDs found in the inputs themselves, i.e. exactly
# the versions the cluster would get (the shared datree catalog lags behind chart releases).
# The datree catalog is only a fallback for CRDs that are not part of the inputs.
#
# Usage:    .github/scripts/kubeconform.sh <file-or-dir>...
# Example:  .github/scripts/kubeconform.sh /tmp/example-cluster.yaml /tmp/example-cluster-helm
# Needs:    docker, yq (mikefarah/yq v4), jq
# Env:      KUBE_VERSION  schema version for built-in kinds (default: example-cluster's k3s)

set -euo pipefail

readonly KUBE_VERSION=${KUBE_VERSION:-1.36.0}
readonly KUBECONFORM_IMAGE=${KUBECONFORM_IMAGE:-ghcr.io/yannh/kubeconform:v0.6.7}
readonly DATREE_CATALOG='https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json'

die() { echo "error: $*" >&2; exit 1; }

# One JSON schema per CRD version, laid out like the datree catalog: <group>/<kind>_<version>.json
generate_crd_schemas() {
  local schemas=$1; shift
  local files
  files=$(find "$@" -type f -name '*.yaml')
  # shellcheck disable=SC2086,SC2016 # file list from find (no spaces); $crd is a yq variable
  yq -N -o json -I0 'select(.kind == "CustomResourceDefinition") | .spec as $crd | $crd.versions[] | {
      "path": $crd.group + "/" + ($crd.names.kind | downcase) + "_" + .name + ".json",
      "schema": .schema.openAPIV3Schema
    }' $files |
    grep . |
    while IFS= read -r line; do
      local path
      path="$schemas/$(jq -r .path <<< "$line")"
      mkdir -p "$(dirname "$path")"
      jq '.schema' <<< "$line" > "$path"
    done
  echo "$(find "$schemas" -name '*.json' | wc -l) schemas from CRDs in the inputs" >&2
}

main() {
  (($# > 0)) || die "usage: $0 <file-or-dir>..."
  local inputs=() input
  for input in "$@"; do
    [[ -e "$input" ]] || die "$input does not exist"
    inputs+=("$(realpath "$input")")
  done

  WORK=$(mktemp -d)
  trap 'rm -rf "$WORK"' EXIT
  generate_crd_schemas "$WORK/schemas" "${inputs[@]}"

  # Every input is mounted at the same path inside the container
  local mounts=() args=()
  for input in "${inputs[@]}"; do
    mounts+=(-v "$input:$input:ro")
    args+=("$input")
  done

  docker run --rm "${mounts[@]}" -v "$WORK/schemas:/schemas:ro" "$KUBECONFORM_IMAGE" \
    -kubernetes-version "$KUBE_VERSION" \
    -schema-location default \
    -schema-location '/schemas/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json' \
    -schema-location "$DATREE_CATALOG" \
    -ignore-missing-schemas -summary \
    "${args[@]}"
}

main "$@"
