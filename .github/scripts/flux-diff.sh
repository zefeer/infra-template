#!/usr/bin/env bash
#
# flux-diff.sh - what a change does to the cluster: compare two builds object by object.
#
# Each side is a directory laid out like the flux-build CI artifact:
#   <dir>/flux-build.yaml   output of flux-build.sh
#   <dir>/helm/*.yaml       output of helm-render.sh
# Together they are everything the cluster would end up with (desired state, Secrets aside).
#
# The report is Markdown: counts, the list of added/removed/changed objects with where each comes
# from (the Flux tree or a HelmRelease), then field-level details from dyff.
# A difference is information, not a failure: the script exits 0 unless it can't run.
#
# Usage:    .github/scripts/flux-diff.sh <base-dir> <head-dir> <report.md>
# Example:  .github/scripts/flux-diff.sh /tmp/base /tmp/head /tmp/diff.md
# Needs:    yq (mikefarah/yq v4), dyff
# Env:      DETAILS_MAX_BYTES  cap for the dyff section (default 200000; Job Summaries max out at 1 MiB)

set -euo pipefail

readonly DETAILS_MAX_BYTES=${DETAILS_MAX_BYTES:-200000}
# join(1) needs both inputs sorted the same way
export LC_ALL=C

die() { echo "error: $*" >&2; exit 1; }

# ---------------------------------------------------------------------------------------------
# Steps
# ---------------------------------------------------------------------------------------------

# 1. One sorted multi-document file per side with what would actually be applied.
#    Objects annotated kustomize.toolkit.fluxcd.io/ssa: Ignore are never applied by kustomize-controller;
#    that is how every app's copies of other apps' values-* ConfigMaps are kept off the cluster.
#    The origin of each object goes into a temporary annotation, removed again in step 2.
normalize() {
  local dir=$1 out=$2 file source
  [[ -s "$dir/flux-build.yaml" ]] || die "$dir/flux-build.yaml is missing"

  # Tag every object with its origin, file by file ("---" keeps documents of two files apart)
  : > "$out.tagged"
  for file in "$dir/flux-build.yaml" "$dir"/helm/*.yaml; do
    [[ -f "$file" ]] || continue
    if [[ "$file" == */helm/* ]]; then source="helm: $(basename "$file" .yaml)"; else source="flux tree"; fi
    echo --- >> "$out.tagged"
    SOURCE="$source" yq 'select(. != null) | .metadata.annotations["flux-diff/source"] = strenv(SOURCE)' "$file" >> "$out.tagged"
  done

  yq ea '
    [ . | select(. != null)
        | select((.metadata.annotations["kustomize.toolkit.fluxcd.io/ssa"] // "") | downcase != "ignore") ]
    | sort_by(.apiVersion + "/" + .kind + "/" + (.metadata.namespace // "") + "/" + .metadata.name)
    | unique_by(.apiVersion + "/" + .kind + "/" + (.metadata.namespace // "") + "/" + .metadata.name)
    | .[] | split_doc
  ' "$out.tagged" > "$out"
  rm -f "$out.tagged"
}

# 2. "<id> TAB <source> TAB <object as one-line JSON>" per object, sorted by id, for join(1).
#    The source annotation is dropped from the JSON so a move between sources alone isn't a change.
index() {
  # shellcheck disable=SC2016
  yq -N '
    [ .apiVersion + "/" + .kind + "/" + (.metadata.namespace // "_") + "/" + .metadata.name,
      .metadata.annotations["flux-diff/source"],
      (del(.metadata.annotations["flux-diff/source"]) | del(.metadata.annotations | select(length == 0)) | to_json(0))
    ] | @tsv' "$1" | grep . | sort -t $'\t' -k1,1 > "$2"
}

strip_source() {
  yq -i 'del(.metadata.annotations["flux-diff/source"]) | del(.metadata.annotations | select(length == 0))' "$1"
}

# "- `kind namespace/name` (source)" lines from index rows
as_list() { awk -F'\t' '{ split($1, p, "/"); n = length(p); ns = (p[n-1] == "_") ? "" : p[n-1] "/"; printf "- `%s %s%s` (%s)\n", p[n-2], ns, p[n], $2 }'; }

# 3. The report.
write_report() {
  local base_idx=$1 head_idx=$2 base=$3 head=$4 report=$5
  local added removed changed
  added=$(join -t $'\t' -v 2 -o 2.1,2.2 "$base_idx" "$head_idx")
  removed=$(join -t $'\t' -v 1 -o 1.1,1.2 "$base_idx" "$head_idx")
  changed=$(join -t $'\t' -o 0,2.2,1.3,2.3 "$base_idx" "$head_idx" | awk -F'\t' '$3 != $4 { print $1 "\t" $2 }')

  count() { if [[ -z "$1" ]]; then echo 0; else wc -l <<< "$1"; fi; }
  local n_added n_removed n_changed
  n_added=$(count "$added"); n_removed=$(count "$removed"); n_changed=$(count "$changed")

  {
    echo "## Flux diff"
    echo
    if ((n_added + n_removed + n_changed == 0)); then
      echo "No changes: the cluster would end up with exactly the same objects."
      return
    fi
    echo "| Added | Removed | Changed |"
    echo "|---:|---:|---:|"
    echo "| $n_added | $n_removed | $n_changed |"
    echo
    section() {
      [[ -n "$2" ]] || return 0
      echo "<details><summary><b>$1</b> ($(count "$2"))</summary>"
      echo
      as_list <<< "$2"
      echo
      echo "</details>"
      echo
    }
    section Added "$added"
    section Removed "$removed"
    section Changed "$changed"

    echo "### Details"
    echo
    echo '```diff'
    local details
    details=$(dyff between --omit-header --color off --output github "$base" "$head" || true)
    if ((${#details} > DETAILS_MAX_BYTES)); then
      head -c "$DETAILS_MAX_BYTES" <<< "$details"
      echo
      echo '```'
      echo
      echo "_Truncated at $DETAILS_MAX_BYTES bytes, the full diff is in the flux-diff artifact._"
    else
      echo "$details"
      echo '```'
    fi
  } > "$report"
}

# ---------------------------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------------------------

main() {
  (($# == 3)) || die "usage: $0 <base-dir> <head-dir> <report.md>"
  command -v yq >/dev/null || die "needs yq"
  command -v dyff >/dev/null || die "needs dyff"
  local base_dir=$1 head_dir=$2 report
  report=$(realpath -m "$3")
  mkdir -p "$(dirname "$report")"

  WORK=$(mktemp -d)
  trap 'rm -rf "$WORK"' EXIT

  normalize "$base_dir" "$WORK/base.yaml"
  normalize "$head_dir" "$WORK/head.yaml"
  index "$WORK/base.yaml" "$WORK/base.idx"
  index "$WORK/head.yaml" "$WORK/head.idx"
  strip_source "$WORK/base.yaml"
  strip_source "$WORK/head.yaml"

  write_report "$WORK/base.idx" "$WORK/head.idx" "$WORK/base.yaml" "$WORK/head.yaml" "$report"
  # Full field-level diff next to the report, for the artifact
  dyff between --omit-header --color off "$WORK/base.yaml" "$WORK/head.yaml" > "${report%.md}.dyff.txt" || true
  echo "Report: $report" >&2
}

main "$@"
