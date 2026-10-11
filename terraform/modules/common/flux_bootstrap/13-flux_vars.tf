## Create config maps with environment variables

resource "kubernetes_config_map_v1" "kcm" {
  depends_on = [
    helm_release.flux2
  ]
  lifecycle {
    ignore_changes = [metadata[0].labels, metadata[0].annotations, data]
  }
  metadata {
    name      = var.env_vars_config_map_name
    namespace = var.flux_namespace
  }
}

resource "kubernetes_config_map_v1_data" "kcm-data" {
  depends_on = [
    helm_release.flux2,
    kubernetes_config_map_v1.kcm
  ]
  metadata {
    name      = kubernetes_config_map_v1.kcm.metadata.0.name
    namespace = kubernetes_config_map_v1.kcm.metadata.0.namespace
  }
  lifecycle {
    replace_triggered_by = [
      kubernetes_config_map_v1.kcm.data
    ]
  }
  data = module.flux_root_manifests.vars_env
}

