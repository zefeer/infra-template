# infra-template

> **Using this template.** Search for `CHANGE-ME` and `example.com` and replace them with your own
> values: GitHub org in `terraform/internal/flux_bootstrap/example_cluster/terragrunt.hcl`, domain
> in Gateway/HTTPRoute hostnames and external-dns `domainFilters`, LoadBalancer IP pool in
> `flux/clusters/internal/example-cluster/_components/cilium/l2-announcement-resources.yaml`.
> Rename `example-cluster` / `example_cluster` to your cluster name.

Template for infrastructure-as-code of a Kubernetes cluster and a few cloud sandboxes:
[FluxCD](https://fluxcd.io/) GitOps for everything running in-cluster, Terraform/Terragrunt for
provisioning and cluster bootstrap.

Terraform's last act is creating a single Flux `Kustomization` named `root`. After that no
application needs `terragrunt apply` — changes reach the cluster through Git.

```
flux/        # GitOps configs reconciled by FluxCD
terraform/   # Terraform modules + Terragrunt environments
```

## `flux/`

Applications are declared, not written. `HelmRelease` and `HelmRepository` manifests exist once, in
`base/_template-base/`; an application in a cluster directory is a Flux `Kustomization` of ~25 lines
that points at a shared template and passes everything app-specific through `postBuild.substitute`.

```
flux/
  base/
    _template-base/       # release.yaml (the only HelmRelease), source-{helm,git}repository.yaml,
                          #   values.yaml and components.yaml (both currently unreferenced)
    _template-helm/       # assembles source-helmrepository + release
    _template-git/        # assembles source-gitrepository + release, chart served from Git
    gateway-api-crds/     # plain-manifest bases for things without a usable chart,
      1.4.1/ 1.6.1/       #   version-pinned directories, picked per cluster
  clusters/
    _vars/                # global vars (kind: Kustomization — the build root for `vars`)
    _values/              # global Helm values (kind: Component)
    _components/          # per-app extra resources for every cluster (Kyverno policies + exceptions)
    internal/             # location "internal"
      _vars/ _values/     # location-level overrides (Components)
      example-cluster/    # example cluster — copy and rename for a real one
        _vars/ _values/   # cluster-level overrides (Components)
        _components/      # per-app extra resources (cert-manager issuer, cilium L2 + Gateway)
        _vars.yaml        # Kustomization `vars` — loads _vars from all three levels
        _replacements.yaml
        kustomization.yaml
        <app>.yaml        # one Kustomization per app
```

### Variable and values layering

`cluster_location` and `cluster_name` are written into `ConfigMap/vars-env` by Terraform and seed
everything else. The same ConfigMap is also written from Git by the `vars` Kustomization — Terraform
owns the identity keys (`lifecycle { ignore_changes = [data] }` plus a separate
`kubernetes_config_map_v1_data`), Git owns the tunables (SSA `merge`), and neither clobbers the
other.

Those variables drive three-level component paths, global → location → cluster:

```
flux/clusters/_vars                                       # global
flux/clusters/${cluster_location}/_vars                   # location
flux/clusters/${cluster_location}/${cluster_name}/_vars    # cluster
```

Helm values use the same three levels. `release.yaml` lists six `valuesFrom` entries — one ConfigMap
and one Secret, each read under three keys (`values.yaml`, `values-${cluster_location}.yaml`,
`values-${cluster_location}-${cluster_name}.yaml`), all optional. Helm merges them in order, so the
layering needs no code; which layer a file lands in is decided by the key its `configMapGenerator`
declares. `behavior: create` means the level owns the value outright, `behavior: merge` means it adds
on top of the shared layer.

Application manifests carry `components: []` on purpose — the root Kustomization injects the three
`_values` directories into every app centrally, scoped by label selector, with
`flux-component: skip_values` as the opt-out.

### The root Kustomization

Created by Terraform, pointing at `flux/clusters/<location>/<cluster>`. Its `patches:` block injects
into every child Kustomization, recursively: `sourceRef`, `substituteFrom` for `vars-env`,
`dependsOn` on `vars`, the `flux-system` namespace for all Flux-kind resources, the `_values`
components, and the SSA annotations that make each app apply only its own values ConfigMap
(`values-DUMMY`, rewritten per app by `_replacements.yaml`).

The manifest itself, and the `vars-env` data, come from
`terraform/modules/common/flux_bootstrap/modules/root_manifests/`: a provider-less module around
`templates/root-kustomization.yaml.tftpl`, so it renders without a cluster
(`terraform init -backend=false && terraform apply`) — the same YAML `flux_bootstrap` applies.

Two `GitRepository` sources back this: `flux-system-cluster-root` is filtered with `ignore:` so
root's revision changes only when this cluster's files or the shared bases change; `flux-system` is
unfiltered and is what children read.

### Adding an application

1. Create `flux/clusters/<location>/<cluster>/<app>.yaml` — a Flux `Kustomization` pointing at
   `./flux/base/_template-helm` with `postBuild.substitute` filled in.
2. Run pre-commit: the generator adds it to the cluster `kustomization.yaml`, writes the
   `values-DUMMY → values-<app>` rule into `_replacements.yaml`, and prunes stale entries.
3. Optionally add `values-<app>.yaml` to `_values/` at the level that should own it and register it
   in that level's `configMapGenerator`.
4. For extra resources, create `_components/<app>/` at the global, location or cluster level;
   pre-commit adds it to the app's `components:`.

## `terraform/`

```
terraform/
  root.hcl                # path-derived config: module discovery, state backend, Vault KV paths
  aws/aws_root.hcl        # AWS provider generation, region resolution
  azure/azure_root.hcl
  internal/
    flux_bootstrap/
      example_cluster/        # ~15 lines of inputs — the whole cluster definition
  modules/
    common/flux_bootstrap/  # numbered so reading order == execution order:
                            #   01 deploy key · 10 Flux install · 11 sources ·
                            #   12 render (modules/root_manifests) · 13 vars-env ·
                            #   14 root Kustomization
    aws/                  # vpc, subnet, route, nat_gateway, internet_gateway, elastic_ip,
                          # iam_role, eks, eks_node_group, _stacks/compute_and_data
    azurerm/              # aks_cluster, aks_extentions, app_configuration, key_vault,
                          # managed_identity, resource_group
    azuread/ad_application/
```

A deployment's directory path *is* its configuration. From
`<location>/<account>/.../<resource_type>/<resource_name>`, `root.hcl` derives the module source
(by searching `modules/` for a directory named after `<resource_type>`), whether to use the on-disk
module or a pinned Git tag (`module_version`), the state backend (Azure Blob with credentials
fetched from Vault, falling back to a local file when `VAULT_TOKEN` is unset), and the Vault KV
path. That is why a per-environment `terragrunt.hcl` is inputs and nothing else.

Each location root (`internal_root.hcl`) holds machine-local settings and is **not committed** — a
fresh clone needs one before `terragrunt plan` will run.

### Adding a cluster

1. `terraform/<location>/flux_bootstrap/<cluster>/terragrunt.hcl` — cluster name, kube API URL and
   client certs, Git org/repo/branch, `flux_git_repo_path_base`.
2. `terragrunt apply` — installs Flux, registers the deploy key, writes `vars-env`, creates `root`.
3. `flux/clusters/<location>/<cluster>/` — `_vars.yaml`, `kustomization.yaml`, `_vars/`, `_values/`,
   and one file per application.

## CI and pre-commit

`.github/workflows/flux-ci.yaml` runs on changes under `flux/` and in the `flux_bootstrap` module. It
builds the whole cluster tree offline the way kustomize-controller does —
`.github/scripts/flux-build.sh`, runnable locally with the same arguments:

1. the root Kustomization and `vars-env` are rendered by `flux_bootstrap/modules/root_manifests`,
   so a PR that changes the root's patches is tested against every app;
2. a throwaway kind cluster (Flux CRDs only, no controllers) stores `vars-env` and the `vars-*`
   ConfigMaps, server-side applied with the same field managers as on the cluster;
3. `flux build ks root --recursive --local-sources` applies root patches, components and
   `postBuild` substitution exactly as on the cluster.

`.github/scripts/helm-render.sh` then templates every HelmRelease of the tree with the values
helm-controller would give it (valuesFrom ConfigMaps, inline values, postRenderers, `.Capabilities`
of the cluster's Kubernetes version and installed CRDs). Values from Secrets are not in Git and are
missing there.

Then, all of it runnable locally with the same arguments:

- `kyverno test` over every `kyverno-test.yaml` under `flux/` — policy logic against hand-made
  pass/fail fixtures, including what the real tree doesn't contain (too broad exceptions, edge cases);
- `.github/scripts/kubeconform.sh` over the tree and the charts, validating custom resources against
  the CRDs the tree and the charts install;
- `.github/scripts/kyverno-check.sh` applies the `ValidatingPolicy` and `PolicyException` objects of
  the tree — exactly what the cluster would enforce — to the tree (a change the cluster would reject
  fails the PR) and, as warnings only, to the rendered charts, until their system components have
  the exceptions they need.

The tree and the rendered charts are uploaded as the `flux-build` artifact.

```bash
.github/scripts/flux-build.sh flux/clusters/internal/example-cluster /tmp/example-cluster.yaml
.github/scripts/helm-render.sh /tmp/example-cluster.yaml /tmp/example-cluster-helm
.github/scripts/kubeconform.sh /tmp/example-cluster.yaml /tmp/example-cluster-helm
.github/scripts/kyverno-check.sh /tmp/example-cluster.yaml
.github/scripts/kyverno-check.sh --warn-only /tmp/example-cluster.yaml /tmp/example-cluster-helm
docker run --rm -v "$PWD":/w -w /w ghcr.io/kyverno/kyverno-cli:v1.19.1 test flux/
```

On pull requests the target branch is built too — with the PR's scripts, run inside a checkout of
the base commit — and `.github/scripts/flux-diff.sh` compares both sides object by object: what is
added, removed or changed in the Flux tree and in the rendered charts, then field-level details
from [dyff](https://github.com/homeport/dyff). The report goes to the run's Job Summary and the
`flux-diff` artifact. Objects annotated `kustomize.toolkit.fluxcd.io/ssa: Ignore` are left out, as
kustomize-controller never applies them. If the base can't be built with the PR's scripts, the diff
is skipped with a notice saying why.

```bash
# <dir> = a directory with flux-build.yaml and helm/, like the flux-build artifact
.github/scripts/flux-diff.sh /tmp/base /tmp/head /tmp/flux-diff/report.md
```

`.github/workflows/policy-checks.yaml` runs gitleaks over the full Git history on every change.

`.pre-commit-config.yaml` runs `gitleaks` plus two local generators that keep the cluster
`kustomization.yaml`, `_replacements.yaml` and the `_vars`/`_values` `configMapGenerator` entries in
sync with the files on disk. The generators run on every commit (`always_run`, since pre-commit never
passes deleted files to hooks) and exit right away when nothing under `flux/` is staged.

## Common commands

```bash
# From an environment directory containing a terragrunt.hcl
terragrunt init
terragrunt plan
terragrunt apply

# Multi-unit Terragrunt stacks
terragrunt run --all plan

tofu fmt -recursive terraform/
```

```bash
# Requires cluster access
flux get kustomizations -A
flux get helmreleases -A
flux reconcile kustomization <name> -n flux-system
```

## Known gaps

Kept here deliberately rather than implied by omission.

- **Secrets are not wired.** No SOPS, SealedSecrets, External Secrets or Vault anywhere under
  `flux/`. The templates reference `Secret/secrets-<app>` and `Secret/secret-values-<app>` as
  `optional: true`, but nothing populates them.
- **The cloud module trees are a library.** No environment under `aws/` or `azure/` instantiates
  them; the exercised path is `internal/`.
- **The Flux chart Terraform installs is resolved at apply time.** HelmReleases in `flux/` are pinned
  (the `require-helmrelease-chart-version` policy enforces it), but `flux_bootstrap` picks the
  `flux2` chart version matching `flux_version` with `helm search` when it runs.
- **One cluster.** The `_vars`/`_values` layering is built for several and currently resolves no
  real conflicts — the location and cluster levels are empty.
