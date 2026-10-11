# Create private key for flux

resource "tls_private_key" "main" {
  algorithm   = "ECDSA"
  ecdsa_curve = "P256"
}

# Gitlab 
# data "gitlab_project" "main" {
#   path_with_namespace = "${var.flux_git_organization}/${var.flux_git_repository}"
# }

# resource "gitlab_deploy_key" "main" {
#   # count = var.bootstrap_flux ? 1 : 0

#   project  = "${var.flux_git_organization}/${var.flux_git_repository}"
#   title    = replace(var.k8s_cluster_name, "_", "-")
#   key      = tls_private_key.main.public_key_openssh
#   can_push = true
# }

# Github
data "github_repository" "main" {
  full_name = "${var.flux_git_organization}/${var.flux_git_repository}"
}

resource "github_repository_deploy_key" "repository_deploy_key" {
  title      = "Flux-${local.cluster_location}-${var.k8s_cluster_name}"
  repository = var.flux_git_repository
  key        = tls_private_key.main.public_key_openssh
  read_only  = "false"
}

locals {
  git_ssh_addr = regex("^.*@(?P<hostname>[\\w\\.]*):*(?P<port>[\\d]*).*", data.github_repository.main.ssh_clone_url)
}

data "shell_script" "ssh_keyscan" {
  lifecycle_commands {
    read = <<-EOF
          echo "{\"known_hosts_entry\": \"$(ssh-keyscan -p ${local.git_ssh_addr.port != "" ? local.git_ssh_addr.port : "22"} ${local.git_ssh_addr.hostname} | grep ecdsa-sha2-nistp256)\"}"
        EOF
  }
}

output "DEBUG_OUTPUTS_01" {
  value = var.debug ? {
    "github ssh_clone_url"           = data.github_repository.main.ssh_clone_url
    "shell_script known_hosts_entry" = data.shell_script.ssh_keyscan.output["known_hosts_entry"]
    "git_ssh_addr"                   = local.git_ssh_addr
    "git_clone_addr"                 = "ssh://git@${local.git_ssh_addr.hostname}/${var.flux_git_organization}/${var.flux_git_repository}.git"
  } : null
}

