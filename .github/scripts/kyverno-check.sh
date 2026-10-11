#!/usr/bin/env bash
#
# kyverno-check.sh - apply the cluster's Kyverno policies to rendered manifests.
#
# Policies and exceptions are taken from the built Flux tree (output of flux-build.sh), i.e.
# exactly what the cluster would enforce. They are applied to the given manifests: by default the
# tree itself, or e.g. the charts rendered by helm-render.sh.
#
#   default       Deny policies fail the run, the way the cluster would reject the objects;
#                 Audit-only ones are reported as warnings
#   --warn-only   every violation becomes a GitHub warning annotation and a line in the Job
#                 Summary, the run never fails - for manifests whose exceptions are still
#                 being worked out
#
# Usage:    .github/scripts/kyverno-check.sh [--warn-only] <flux-build-output> [<file-or-dir>...]
# Example:  .github/scripts/kyverno-check.sh /tmp/example-cluster.yaml
#           .github/scripts/kyverno-check.sh --warn-only /tmp/example-cluster.yaml /tmp/example-cluster-helm
# Needs:    docker, yq (mikefarah/yq v4)

set -euo pipefail

readonly KYVERNO_CLI_IMAGE=${KYVERNO_CLI_IMAGE:-ghcr.io/kyverno/kyverno-cli:v1.19.1}

die() { echo "error: $*" >&2; exit 1; }

# Policies and exceptions as they would be deployed
extract_policies() {
  yq 'select(.kind == "ValidatingPolicy")' "$TREE" > "$WORK/policies.yaml"
  yq 'select(.kind == "PolicyException")' "$TREE" > "$WORK/exceptions.yaml"
}

# Objects to check, each once. Dropped: Kyverno's own objects, CRDs (no policy targets them),
# and objects annotated ssa: Ignore, which kustomize-controller never applies (every app's
# copies of other apps' values-* ConfigMaps). Duplicates would also make the CLI's fake client panic.
collect_resources() {
  local files
  files=$(find "$@" -type f -name '*.yaml')
  # shellcheck disable=SC2086 # file list from find, paths without spaces
  yq ea '
    [ . | select(. != null)
        | select(.kind != "ValidatingPolicy" and .kind != "MutatingPolicy" and .kind != "PolicyException")
        | select(.kind != "CustomResourceDefinition")
        | select((.metadata.annotations["kustomize.toolkit.fluxcd.io/ssa"] // "") | downcase != "ignore") ]
    | unique_by(.apiVersion + "/" + .kind + "/" + (.metadata.namespace // "") + "/" + .metadata.name)
    | .[] | split_doc' $files > "$WORK/resources.yaml"
}

run_kyverno() {
  local exceptions=()
  [[ -s "$WORK/exceptions.yaml" ]] && exceptions=(--exceptions exceptions.yaml)
  docker run --rm -v "$WORK":/w -w /w "$KYVERNO_CLI_IMAGE" apply policies.yaml \
    --resource resources.yaml "${exceptions[@]}" --audit-warn --remove-color
}

# "policy <name> -> resource <ns/Kind/name> failed ..." lines -> annotations + Job Summary
report_warnings() {
  local log=$1 violations
  violations=$(sed -nE 's/^policy ([^ ]+) -> resource ([^ ]+) failed.*/\1 \2/p' "$log" | sort -u)
  if [[ -z "$violations" ]]; then
    echo "No policy violations." >&2
    return
  fi

  local policy resource
  while read -r policy resource; do
    echo "::warning title=Kyverno $policy::$resource violates $policy (warning only)"
  done <<< "$violations"

  [[ -n "${GITHUB_STEP_SUMMARY:-}" ]] || return 0
  {
    echo "### Kyverno: $(wc -l <<< "$violations") violation(s), warnings only"
    echo
    echo "| Policy | Resource |"
    echo "|---|---|"
    while read -r policy resource; do echo "| \`$policy\` | \`$resource\` |"; done <<< "$violations"
    echo
  } >> "$GITHUB_STEP_SUMMARY"
}

main() {
  local warn_only=false
  [[ "${1:-}" == --warn-only ]] && { warn_only=true; shift; }
  (($# >= 1)) || die "usage: $0 [--warn-only] <flux-build-output> [<file-or-dir>...]"
  TREE=$(realpath "$1"); shift
  [[ -s "$TREE" ]] || die "$TREE is empty or missing"
  (($# > 0)) || set -- "$TREE"

  WORK=$(mktemp -d)
  trap 'rm -rf "$WORK"' EXIT
  # mktemp creates it 0700; the CLI in the container doesn't run as this user
  chmod 755 "$WORK"

  extract_policies
  [[ -s "$WORK/policies.yaml" ]] || { echo "No ValidatingPolicy in the tree, nothing to check." >&2; return 0; }
  collect_resources "$@"

  if [[ "$warn_only" == true ]]; then
    run_kyverno 2>&1 | tee "$WORK/apply.log" || true
    # Violations are tolerated here, the CLI failing to run is not
    grep -q '^pass: ' "$WORK/apply.log" || die "kyverno apply did not run, see its output above"
    report_warnings "$WORK/apply.log"
  else
    run_kyverno
  fi
}

main "$@"
