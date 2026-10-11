data "shell_script" "get_helm_chart_version" {
  for_each = { for k, v in ["flux2", "flux2-sync"] : v => v }
  # depends_on = [ null_resource.helm_repo_add ]
  lifecycle_commands {
    read = <<-EOF
          helm repo add fluxcd-community https://fluxcd-community.github.io/helm-charts
          helm repo update fluxcd-community
          version=$(helm search repo -l | awk '$1 ~ "fluxcd-community/${each.value}" %{if var.flux_version != null}&& $3 == "${var.flux_version}"%{endif} {print $2; exit}')
          if [[ -z "$version" ]]; then
            version=$(helm search repo -l | awk '$1 ~ "fluxcd-community/${each.value}" {print $2; exit}')
          fi
          echo "{\"chart_version\": \"$version\"}"
        EOF
  }
}

locals {
  chart_version = { for k, v in data.shell_script.get_helm_chart_version : k => v.output.chart_version }
}

output "DEBUG_OUTPUTS_02" {
  value = {
    "chart_version"       = local.chart_version
    "chart_version_flux2" = local.chart_version["flux2"]
  }
}

resource "helm_release" "flux2" {
  depends_on = [data.shell_script.get_helm_chart_version]

  name             = "flux-system"
  namespace        = var.flux_namespace
  repository       = "https://fluxcd-community.github.io/helm-charts"
  chart            = "flux2"
  version          = local.chart_version["flux2"] != "" ? local.chart_version["flux2"] : null
  wait             = true
  create_namespace = true
  force_update     = true
  timeout          = 3600
  disable_webhooks = lookup(var.flux_additional_helm_release_options, "disable_webhooks", false)
}