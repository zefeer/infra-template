#!/usr/bin/env bash
#
# helm-render.sh - render every HelmRelease of a built Flux tree, the way helm-controller would.
#
# Input is the output of flux-build.sh. For each HelmRelease the chart is templated with the
# values helm-controller would give it, and the result goes to <output-dir>/<namespace>_<name>.yaml.
#
# Usage:    .github/scripts/helm-render.sh <flux-build-output> <output-dir>
# Example:  .github/scripts/helm-render.sh /tmp/example-cluster.yaml /tmp/example-cluster-helm
# Needs:    helm, kubectl (for kustomize), yq (mikefarah/yq v4)
# Env:      KUBE_VERSION  Kubernetes version charts see in .Capabilities (default: example-cluster's k3s)
#
# What is reproduced
# ------------------
#   * chart source       HelmRepository (https or oci) from the tree; GitRepository charts from this
#                        checkout (both GitRepositories in this repo point at it)
#   * values             valuesFrom ConfigMaps in order, then inline spec.values on top
#   * install.crds       CRDs included unless the HelmRelease says Skip
#   * postRenderers      kustomize patches, applied to the rendered chart
#   * .Capabilities      the Kubernetes version above, plus API versions of every CRD the tree and
#                        the charts install (charts like cilium refuse to render a ServiceMonitor
#                        without monitoring.coreos.com/v1 being available)
#
# What can't be reproduced offline
# --------------------------------
#   * valuesFrom Secrets - they are not in Git, so values from them are missing here
#   * lookup() in templates returns nothing without a cluster
#   * the labels helm-controller adds to every object (helm.toolkit.fluxcd.io/name, ...)

set -euo pipefail

readonly KUBE_VERSION=${KUBE_VERSION:-1.36.0}

# ---------------------------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------------------------

die()      { echo "error: $*" >&2; exit 1; }
warn()     { echo "warning: $*" >&2; }
step()     { echo "::group::$*" >&2; }
step_end() { echo "::endgroup::" >&2; }

require_tools() {
  local tool missing=()
  for tool in helm kubectl yq; do
    command -v "$tool" >/dev/null || missing+=("$tool")
  done
  ((${#missing[@]} == 0)) || die "missing tools: ${missing[*]}"
}

# The HelmRelease being processed; exported so yq expressions can use strenv(HR_NS)/strenv(HR_NAME)
export HR_NS="" HR_NAME=""

# Query the current HelmRelease. -N drops the "---" separators yq prints between documents.
hr_get() { yq -N "select(.metadata.name == strenv(HR_NAME) and .metadata.namespace == strenv(HR_NS)) | $1" "$RELEASES"; }

# ---------------------------------------------------------------------------------------------
# Steps
# ---------------------------------------------------------------------------------------------

# 1. Pull what we need out of the (large) tree once. Every app generates every values-*
#    ConfigMap, so ConfigMaps are deduplicated by namespace/name; the copies are identical.
extract_objects() {
  step "1. Extract HelmReleases, HelmRepositories and ConfigMaps from $TREE"
  yq 'select(.kind == "HelmRelease")' "$TREE" > "$RELEASES"
  yq 'select(.kind == "HelmRepository")' "$TREE" > "$REPOSITORIES"
  yq ea '[select(.kind == "ConfigMap")] | unique_by(.metadata.namespace + "/" + .metadata.name) | .[] | split_doc' \
    "$TREE" > "$CONFIGMAPS"
  yq -N '.metadata.namespace + " " + .metadata.name' "$RELEASES" | grep . > "$RELEASE_LIST" ||
    die "no HelmRelease in $TREE"
  echo "$(wc -l < "$RELEASE_LIST") HelmReleases" >&2
  step_end
}

# Values files for one HelmRelease, in the order helm-controller merges them (later wins).
# Prints the helm arguments (-f <file> ...) one per line.
values_args() {
  local dir="$WORK/values/${HR_NS}_${HR_NAME}" i=0 kind name key optional file
  mkdir -p "$dir"

  while IFS=$'\t' read -r kind name key optional; do
    [[ -n "$kind" ]] || continue
    i=$((i + 1))
    file="$dir/$i-$kind-$name-$key"
    case "$kind" in
      ConfigMap)
        CM_NAME="$name" CM_NS="$HR_NS" KEY="$key" yq -N \
          'select(.metadata.name == strenv(CM_NAME) and .metadata.namespace == strenv(CM_NS)) | .data[strenv(KEY)] // ""' \
          "$CONFIGMAPS" > "$file"
        ;;
      Secret)
        # Not in Git; an optional Secret is simply absent here, a required one would fail on the cluster too
        [[ "$optional" == true ]] || warn "$HR_NS/$HR_NAME: required Secret $name can't be resolved offline"
        continue
        ;;
    esac
    if [[ -s "$file" ]]; then
      printf -- '-f\n%s\n' "$file"
    elif [[ "$optional" != true ]]; then
      die "$HR_NS/$HR_NAME: required $kind $name has no key $key"
    fi
  done < <(hr_get '.spec.valuesFrom[]? | [.kind, .name, (.valuesKey // "values.yaml"), (.optional // false)] | @tsv')

  # Inline values override everything from valuesFrom
  if [[ "$(hr_get '.spec.values != null')" == true ]]; then
    hr_get '.spec.values' > "$dir/inline.yaml"
    printf -- '-f\n%s\n' "$dir/inline.yaml"
  fi
}

# Chart reference for helm template: repo chart, oci://... or a local path.
chart_args() {
  local chart version source_kind source_name url type
  chart=$(hr_get '.spec.chart.spec.chart')
  version=$(hr_get '.spec.chart.spec.version // ""')
  source_kind=$(hr_get '.spec.chart.spec.sourceRef.kind')
  source_name=$(hr_get '.spec.chart.spec.sourceRef.name')

  case "$source_kind" in
    HelmRepository)
      url=$(SRC="$source_name" yq -N 'select(.metadata.name == strenv(SRC)) | .spec.url' "$REPOSITORIES" | head -1)
      type=$(SRC="$source_name" yq -N 'select(.metadata.name == strenv(SRC)) | .spec.type // "default"' "$REPOSITORIES" | head -1)
      [[ -n "$url" ]] || die "$HR_NS/$HR_NAME: HelmRepository $source_name not found in the tree"
      if [[ "$type" == oci ]]; then
        printf '%s\n' "${url%/}/$chart"
      else
        printf '%s\n' "$chart" --repo "$url"
      fi
      # Passed as is: for OCI the version is the tag, and "v26.7.1" is not the same tag as "26.7.1"
      [[ -z "$version" || "$version" == "*" ]] || printf '%s\n' --version "$version"
      ;;
    GitRepository)
      printf '%s\n' "./${chart#./}"
      ;;
    *)
      die "$HR_NS/$HR_NAME: charts from $source_kind are not supported"
      ;;
  esac
}

# helm template for one HelmRelease, postRenderers applied. Returns helm's exit code.
render_release() {
  local out=$1 release_name target_ns
  local -a chart values extra=()
  target_ns=$(hr_get '.spec.targetNamespace // .metadata.namespace')
  # helm-controller's default release name is <targetNamespace>-<name> when targetNamespace is set
  release_name=$(hr_get '.spec.releaseName // ""')
  if [[ -z "$release_name" ]]; then
    release_name=$HR_NAME
    [[ "$(hr_get '.spec.targetNamespace // ""')" == "" ]] || release_name="$target_ns-$HR_NAME"
  fi
  [[ "$(hr_get '.spec.install.crds // "Create"')" == Skip ]] || extra+=(--include-crds)

  # Via files, not <(...): a die inside a process substitution would not stop the script
  chart_args > "$out.chart-args"
  values_args > "$out.values-args"
  mapfile -t chart < "$out.chart-args"
  mapfile -t values < "$out.values-args"
  rm -f "$out.chart-args" "$out.values-args"

  helm template "$release_name" "${chart[@]}" --namespace "$target_ns" "${values[@]}" \
    --kube-version "$KUBE_VERSION" "${API_VERSION_ARGS[@]}" --skip-tests "${extra[@]}" \
    > "$out.raw" 2> "$out.err" || return
  # For OCI charts helm prints "Pulled: <ref>" and "Digest: <sha>" to stdout, before the manifests
  awk 'head && /^(Pulled|Digest): / { next } { head = 0; print }' head=1 "$out.raw" > "$out"
  rm -f "$out.raw"

  apply_post_renderers "$out"
}

# postRenderers[].kustomize: patches (and images) applied to the rendered chart, one renderer
# after another, like helm-controller does.
apply_post_renderers() {
  local out=$1 n i dir
  n=$(hr_get '.spec.postRenderers | length')
  for ((i = 0; i < n; i++)); do
    dir="$WORK/postrender/${HR_NS}_${HR_NAME}_$i"
    mkdir -p "$dir"
    cp "$out" "$dir/rendered.yaml"
    I=$i hr_get '.spec.postRenderers[env(I)].kustomize | {
      "apiVersion": "kustomize.config.k8s.io/v1beta1",
      "kind": "Kustomization",
      "resources": ["rendered.yaml"],
      "patches": (.patches // []),
      "images": (.images // [])
    }' > "$dir/kustomization.yaml"
    kubectl kustomize "$dir" > "$out"
  done
}

# 2. API versions charts may check in .Capabilities: CRDs from the tree, then (after a first
#    render) the CRDs the charts themselves install. A chart failing in this pass is fine.
discover_api_versions() {
  step "2. Discover API versions (first render pass, failures expected)"
  API_VERSION_ARGS=()
  mkdir -p "$WORK/pass1"
  while read -r HR_NS HR_NAME; do
    render_release "$WORK/pass1/${HR_NS}_${HR_NAME}.yaml" < /dev/null || true
  done < "$RELEASE_LIST"

  local api
  while read -r api; do
    API_VERSION_ARGS+=(--api-versions "$api")
  done < <(cat "$TREE" "$WORK"/pass1/*.yaml |
    yq -N 'select(.kind == "CustomResourceDefinition") | .spec.group + "/" + .spec.versions[].name' |
    grep . | sort -u)
  echo "$((${#API_VERSION_ARGS[@]} / 2)) API versions from CRDs" >&2
  step_end
}

# 3. The real render. Any failure now is a real problem with the chart or its values.
render_all() {
  step "3. Render HelmReleases (Kubernetes $KUBE_VERSION)"
  local out failed=0
  while read -r HR_NS HR_NAME; do
    out="$OUT_DIR/${HR_NS}_${HR_NAME}.yaml"
    if render_release "$out" < /dev/null; then
      printf '  %-40s %7s lines\n' "$HR_NS/$HR_NAME" "$(wc -l < "$out")" >&2
      rm -f "$out.err"
    else
      echo "  $HR_NS/$HR_NAME FAILED:" >&2
      sed 's/^/    /' "$out.err" >&2
      rm -f "$out" "$out.raw" "$out.err"
      failed=$((failed + 1))
    fi
  done < "$RELEASE_LIST"
  step_end
  ((failed == 0)) || die "$failed HelmRelease(s) failed to render"
}

# ---------------------------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------------------------

main() {
  (($# == 2)) || die "usage: $0 <flux-build-output> <output-dir>, e.g. /tmp/example-cluster.yaml /tmp/example-cluster-helm"
  require_tools

  TREE=$(realpath "$1")
  OUT_DIR=$(realpath -m "$2")
  [[ -s "$TREE" ]] || die "$TREE is empty or missing"
  # GitRepository charts are paths in this checkout
  cd "$(git rev-parse --show-toplevel)"
  mkdir -p "$OUT_DIR"

  WORK=$(mktemp -d)
  trap 'rm -rf "$WORK"' EXIT
  RELEASES="$WORK/helmreleases.yaml"
  REPOSITORIES="$WORK/helmrepositories.yaml"
  CONFIGMAPS="$WORK/configmaps.yaml"
  RELEASE_LIST="$WORK/releases.txt"   # "<namespace> <name>" per line

  extract_objects
  discover_api_versions
  render_all
  echo "Rendered $(wc -l < "$RELEASE_LIST") HelmReleases into $OUT_DIR" >&2
}

main "$@"
