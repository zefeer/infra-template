#!/usr/bin/env bash
#
# flux-build.sh - build a cluster's whole Flux tree without the cluster.
#
# The output is what kustomize-controller would apply: every Flux Kustomization under the
# cluster directory, built with root's patches (including the patches root adds for
# grandchildren), components and postBuild variable substitution.
#
# Usage:    .github/scripts/flux-build.sh <cluster-path> <output-file>
# Example:  .github/scripts/flux-build.sh flux/clusters/internal/example-cluster /tmp/example-cluster.yaml
# Needs:    terraform, kind (with docker), flux, kubectl, yq (mikefarah/yq v4)
#
# How it works
# ------------
# `flux build ks --recursive` builds Kustomizations with the same library as kustomize-controller.
# Two things it can't get from Git:
#
#   * The root Kustomization and the vars-env ConfigMap. Terraform creates them, so we render
#     them with the same Terraform module flux_bootstrap uses (no providers, no cluster needed).
#   * The ConfigMaps used by postBuild.substituteFrom. flux build reads them from a Kubernetes
#     API, so we start a throwaway kind cluster and only store objects in it. No Flux controllers
#     run there and nothing is reconciled.
#
# Steps (see main at the bottom):
#   1. render root + vars-env       terraform, root_manifests module
#   2. start a kind cluster         own name and kubeconfig, deleted on exit
#   3. load Flux CRDs + step 1      so the API knows the Kustomization kind
#   4. build root                   the cluster directory, without recursion
#   5. load vars-* ConfigMaps       built from the vars Kustomization found in step 4
#   6. build the whole tree         recursively, into <output-file>
#
# The kind cluster has its own kubeconfig, so the script never touches your current cluster.

set -euo pipefail

# Where flux_bootstrap renders the root Kustomization and vars-env from
readonly ROOT_MANIFESTS_MODULE=terraform/modules/common/flux_bootstrap/modules/root_manifests

# ---------------------------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------------------------

die() { echo "error: $*" >&2; exit 1; }

# Collapsible log sections on GitHub Actions; plain markers when run locally
step()     { echo "::group::$*" >&2; }
step_end() { echo "::endgroup::" >&2; }

# Server-side apply from stdin as a given field manager. Using the same managers as on the real
# cluster matters: the vars Kustomization also generates a vars-env ConfigMap, and on the cluster
# Flux merges its keys into Terraform's vars-env. A plain `kubectl apply` would replace it instead.
apply_as() { kubectl apply --server-side --field-manager="$1" -f - >/dev/null; }

require_tools() {
  local tool missing=()
  for tool in terraform kind docker flux kubectl yq; do
    command -v "$tool" >/dev/null || missing+=("$tool")
  done
  ((${#missing[@]} == 0)) || die "missing tools: ${missing[*]}"
}

# ---------------------------------------------------------------------------------------------
# Steps
# ---------------------------------------------------------------------------------------------

# 1. Root Kustomization and vars-env, exactly as flux_bootstrap applies them.
#    Module inputs come from the cluster path: <path_base>/clusters/<location>/<cluster>.
render_terraform_objects() {
  local path_base location cluster
  # ponytail: assumes a single-segment flux_git_repo_path_base ("flux")
  IFS=/ read -r path_base _ location cluster <<< "${CLUSTER_PATH%/}"

  step "1. Render root Kustomization and vars-env for $location/$cluster"
  local tf=(terraform -chdir="$ROOT_MANIFESTS_MODULE")
  "${tf[@]}" init -backend=false -input=false >/dev/null
  "${tf[@]}" apply -auto-approve -input=false -state="$WORK/tfstate" \
    -var "cluster_location=$location" \
    -var "k8s_cluster_name=$cluster" \
    -var "flux_git_repo_path_base=$path_base" >/dev/null

  "${tf[@]}" output -state="$WORK/tfstate" -raw root_kustomization_yaml > "$ROOT_KS"

  # Namespace and ConfigMap name are read from the rendered root, so they can't drift from it
  FLUX_NS=$(yq '.metadata.namespace' "$ROOT_KS")
  local vars_env_name
  vars_env_name=$(yq '.spec.postBuild.substituteFrom[0].name' "$ROOT_KS")

  "${tf[@]}" output -state="$WORK/tfstate" -json vars_env |
    NAME="$vars_env_name" NS="$FLUX_NS" yq -p json -o yaml '{
      "apiVersion": "v1",
      "kind": "ConfigMap",
      "metadata": {"name": strenv(NAME), "namespace": strenv(NS)},
      "data": .
    }' > "$VARS_ENV_CM"
  step_end
}

# 2. Throwaway cluster used only as storage for ConfigMaps and Kustomizations.
start_kind_cluster() {
  step "2. Start throwaway kind cluster $KIND_NAME"
  kind create cluster --quiet --name "$KIND_NAME" --kubeconfig "$KUBECONFIG" --wait 120s
  step_end
}

# 3. Flux CRDs (flux build checks the API knows the Kustomization kind) and the Terraform objects.
load_crds_and_terraform_objects() {
  step "3. Load Flux CRDs (no controllers) and the objects Terraform creates"
  flux install --export | yq 'select(.kind == "CustomResourceDefinition")' | apply_as kustomize-controller
  kubectl wait --for condition=established crd --all --timeout=60s >/dev/null
  kubectl create namespace "$FLUX_NS" >/dev/null
  # flux build also reads the Kustomization it builds from the API, even with --kustomization-file
  cat "$VARS_ENV_CM" <(echo ---) "$ROOT_KS" | apply_as terraform
  step_end
}

# 4. Root alone: its output holds the child Kustomizations, including vars.
#    Every build writes to a file first, so a broken build stops with its own error.
build_root() {
  step "4. Build root ($CLUSTER_PATH)"
  flux build ks root -n "$FLUX_NS" --kustomization-file "$ROOT_KS" --path "$CLUSTER_PATH" > "$ROOT_BUILD"
  step_end
}

# 5. Every app substitutes from vars-<app> ConfigMaps, which the vars Kustomization generates.
#    They have to be in the API before the full build, so vars is built and loaded on its own.
load_vars_configmaps() {
  step "5. Build the vars Kustomization and load its ConfigMaps"
  yq 'select(.kind == "Kustomization" and .metadata.name == "vars")' "$ROOT_BUILD" > "$VARS_KS"
  [[ -s "$VARS_KS" ]] || die "root built no Kustomization named vars"
  apply_as kustomize-controller < "$VARS_KS"

  flux build ks vars -n "$FLUX_NS" --kustomization-file "$VARS_KS" \
    --path "$(yq '.spec.path' "$VARS_KS")" > "$VARS_BUILD"
  yq 'select(.kind == "ConfigMap")' "$VARS_BUILD" | apply_as kustomize-controller
  step_end
}

# 6. The whole tree. Both GitRepositories Terraform creates point at this checkout:
#    <ns>-cluster-root is root's source, <ns> is the one root patches into every child.
build_tree() {
  step "6. Build the whole tree"
  local sources="GitRepository/$FLUX_NS/$FLUX_NS=.,GitRepository/$FLUX_NS/$FLUX_NS-cluster-root=."
  flux build ks root -n "$FLUX_NS" --kustomization-file "$ROOT_KS" --path "$CLUSTER_PATH" \
    --recursive --local-sources "$sources" > "$OUT"
  step_end
}

print_summary() {
  echo "Built $(yq ea '[.kind] | length' "$OUT") objects into $OUT:" >&2
  yq ea '[.kind] | group_by(.) | map(.[0] + "=" + (length | tostring)) | join(" ")' "$OUT" >&2
}

# ---------------------------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------------------------

main() {
  (($# == 2)) || die "usage: $0 <cluster-path> <output-file>, e.g. flux/clusters/internal/example-cluster /tmp/out.yaml"
  require_tools

  OUT=$(realpath -m "$2")
  mkdir -p "$(dirname "$OUT")"
  cd "$(git rev-parse --show-toplevel)"
  CLUSTER_PATH=$1
  [[ -f "$CLUSTER_PATH/kustomization.yaml" ]] || die "no kustomization.yaml in $CLUSTER_PATH"

  # Everything temporary lives in WORK and is removed on exit, together with the kind cluster
  WORK=$(mktemp -d)
  KIND_NAME="flux-build-$$"
  export KUBECONFIG="$WORK/kubeconfig"
  trap 'kind delete cluster --name "$KIND_NAME" --kubeconfig "$KUBECONFIG" >/dev/null 2>&1 || true; rm -rf "$WORK"' EXIT

  ROOT_KS="$WORK/root-kustomization.yaml"  # rendered by Terraform
  VARS_ENV_CM="$WORK/vars-env.yaml"        # rendered by Terraform
  ROOT_BUILD="$WORK/root-build.yaml"       # step 4 output
  VARS_KS="$WORK/vars-kustomization.yaml"  # the vars Kustomization from step 4
  VARS_BUILD="$WORK/vars-build.yaml"       # step 5 output

  render_terraform_objects
  start_kind_cluster
  load_crds_and_terraform_objects
  build_root
  load_vars_configmaps
  build_tree
  print_summary
}

main "$@"
