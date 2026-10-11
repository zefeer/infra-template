terraform {
  required_providers {
    github = {
      source  = "integrations/github"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.17.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 3.0.1"
    }
    kubectl = {
      source  = "alekc/kubectl"
      version = ">= 2.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = ">=3.1.0"
    }
    shell = {
      source  = "scottwinkler/shell"
      version = ">=1.7.3"
    }
  }
}

provider "kubernetes" {
  host                   = var.k8s_url
  token                  = var.k8s_user_token
  cluster_ca_certificate = var.k8s_cluster_ca
  insecure               = var.k8s_insecure
  client_key             = var.k8s_user_key
  client_certificate     = var.k8s_user_cert
}
provider "helm" {
  kubernetes = {
    host                   = var.k8s_url
    token                  = var.k8s_user_token
    cluster_ca_certificate = var.k8s_cluster_ca
    insecure               = var.k8s_insecure
    client_key             = var.k8s_user_key
    client_certificate     = var.k8s_user_cert
  }
}
provider "kubectl" {
  host                   = var.k8s_url
  token                  = var.k8s_user_token
  cluster_ca_certificate = var.k8s_cluster_ca
  insecure               = var.k8s_insecure
  client_key             = var.k8s_user_key
  client_certificate     = var.k8s_user_cert
  load_config_file       = false
}
provider "github" {
  owner = try(var.flux_git_organization, "")
  token = var.github_token
}
provider "shell" {
  interpreter = ["/bin/bash", "-c"]
}
