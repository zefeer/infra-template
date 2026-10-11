## Create flux source git repositories

# Create source access secret
resource "kubernetes_secret_v1" "source_auth" {
  depends_on = [
    helm_release.flux2
  ]
  metadata {
    name      = "${var.flux_namespace}-auth"
    namespace = var.flux_namespace
  }
  data = {
    "identity"     = tls_private_key.main.private_key_openssh
    "identity.pub" = tls_private_key.main.public_key_openssh
    "known_hosts"  = data.shell_script.ssh_keyscan.output["known_hosts_entry"]
  }
}

# Create source limited to cluster root only
resource "kubectl_manifest" "source_cluster_root" {
  depends_on = [
    helm_release.flux2
  ]
  yaml_body = <<YAML
apiVersion: source.toolkit.fluxcd.io/v1
kind: GitRepository
metadata:
  name: "${var.flux_namespace}-cluster-root"
  namespace: "${var.flux_namespace}"
spec:
  ignore: |
    # exclude all
    /*
    # include cluster root dir
    !/${var.flux_git_repo_path_base}/clusters/${local.cluster_location}/${var.k8s_cluster_name}/*.yaml
    # include shared templates dir
    !/${var.flux_git_repo_path_base}/base/**/*.yaml
  interval: 5m0s
  ref:
    ${var.flux_git_repo_reference_type}: ${var.flux_git_repo_reference_value}
  secretRef:
    name: "${kubernetes_secret_v1.source_auth.metadata[0].name}"
  timeout: 1m0s
  url: "ssh://git@${local.git_ssh_addr.hostname}/${var.flux_git_organization}/${var.flux_git_repository}.git"
YAML
}

# Create source without limits
resource "kubectl_manifest" "source_base" {
  depends_on = [
    helm_release.flux2
  ]
  yaml_body = <<YAML
apiVersion: source.toolkit.fluxcd.io/v1
kind: GitRepository
metadata:
  name: "${var.flux_namespace}"
  namespace: "${var.flux_namespace}"
spec:
  interval: 1m0s
  ref:
    ${var.flux_git_repo_reference_type}: ${var.flux_git_repo_reference_value}
  secretRef:
    name: "${kubernetes_secret_v1.source_auth.metadata[0].name}"
  timeout: 1m0s
  url: "ssh://git@${local.git_ssh_addr.hostname}/${var.flux_git_organization}/${var.flux_git_repository}.git"
YAML
}

