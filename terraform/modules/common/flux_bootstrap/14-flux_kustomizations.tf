## Manifest: modules/root_manifests/templates/root-kustomization.yaml.tftpl
resource "kubectl_manifest" "cluster_root_kustomization" {
  depends_on = [
    helm_release.flux2,
    kubectl_manifest.source_cluster_root,
    kubectl_manifest.source_base,
    # Was implied by reading the ConfigMap name from this resource; the template now gets the name as a variable
    kubernetes_config_map_v1.kcm,
  ]
  force_conflicts = true
  yaml_body       = module.flux_root_manifests.root_kustomization_yaml
}
