locals {
  deployments_root_dir   = get_parent_terragrunt_dir()
  relative_path          = path_relative_to_include()
  path_parts             = compact(split("/", local.relative_path))

  location      = local.path_parts[0]
  account       = local.path_parts[1]
  resource_type = element(local.path_parts, length(local.path_parts) - 2) # second-to-last element
  resource_name = element(local.path_parts, length(local.path_parts) - 1) # last element

  module_version = try(read_terragrunt_config("versions.hcl").locals.module_version, "local") # path from parent_dir

  # Get a list of every possible tfvars path between deployments_root_dir
  # and the path of the deployment
  possible_config_locations = [for i in range(0, length(local.path_parts) + 1) :
    join("/", concat(
      [local.deployments_root_dir],
      slice(local.path_parts, 0, i),
      ["terraform.tfvars"]
    ))
  ]

  # Add the current working directory to the Git safe directory list.
  # This is used for local development to avoid Git warnings about the directory not being safe.
  # _git_safe_repo_dir   = run_cmd("git", "config", "--global", "--add", "safe.directory", "${get_repo_root()}")

  # Fetch Azure credentials from Vault for the remote state backend.
  # If VAULT_TOKEN is not set (or Vault is unreachable), the shell returns '{}' so
  # the JSON decode falls back to an empty map and use_local_state becomes true.
  vault_state_raw = run_cmd(
    "--terragrunt-quiet", "sh", "-c",
    "[ -z \"$VAULT_TOKEN\" ] && echo '{}' || curl -sf -H 'X-Vault-Request: true' -H \"X-Vault-Token: $VAULT_TOKEN\" \"${get_env("VAULT_ADDR", "")}/v1/kvv2/data/azure/user_account\" || echo '{}'"
  )
  vault_state_credentials = try(jsondecode(local.vault_state_raw).data.data, {})
  use_local_state         = lookup(local.vault_state_credentials, "SUBSCRIPTION_ID", "") == ""

  # Discover the Terraform module directory that matches the resource_type component of the deployment path.
  discovered_module_path = trimprefix(run_cmd("--terragrunt-quiet", "find", "${get_repo_root()}/terraform/modules/", "-type", "d", "-name", "${local.resource_type}", "-not", "-path", "*/_stacks/*"), get_repo_root())

  # If multiple module directories match (e.g. same resource type across clouds), keep only the one
  # whose path contains the account name.
  resolved_module_path = length(split("\n", local.discovered_module_path)) > 1 ? join(",", [for path in split("\n", local.discovered_module_path) : path if strcontains(path, local.account)]) : local.discovered_module_path

  module_source_git   = "git::${get_path_to_repo_root()}//${local.resolved_module_path}?ref=internal_${local.resource_type}@${local.module_version}"
  module_source_local = "${get_repo_root()}${local.resolved_module_path}"
  # module_source_local = "${get_path_to_repo_root()}/${local.resolved_module_path}"  

  # Use the local filesystem path when version is "local"; otherwise reference a pinned Git tag.
  module_source = local.module_version != "local" ? local.module_source_git : local.module_source_local


  # Vault KV path construction for child modules
  vault_mount_path    = "kvv2"
  vault_kv_private_ns = "private"

  # Names of all module directories (leaf dirs under modules/) — used to strip module-name
  # components from the deployment path when building the Vault KV path.
  module_dir_names       = run_cmd("--terragrunt-quiet", "find", "${get_repo_root()}/terraform/modules/", "-type", "d", "-links", "2", "-exec", "basename", "{}", ";")
  path_parts_no_modules  = join("/", [for part in split("/", local.relative_path) : part if contains(split("\n", local.module_dir_names), part) == false])

  # For non-internal locations: use first 4 deployment path components as the Vault KV subpath.
  vault_kv_path_by_depth = length(split("/", local.relative_path)) > 3 ? join("/", concat([local.vault_kv_private_ns], slice(split("/", local.relative_path), 0, 4))) : null

  # For internal locations: strip module names from the path to avoid leaking module dirs into Vault paths.
  module_vault_path = local.location == "internal" ? "${local.vault_kv_private_ns}/${local.path_parts_no_modules}" : local.vault_kv_path_by_depth

  # debug = run_cmd("echo", "path_parts_no_modules = ${local.path_parts_no_modules}")
  # debug2 = run_cmd("echo", "module_source = ${local.module_source}")
  # debug3 = run_cmd("echo", "discovered_module_path = ${local.discovered_module_path}")
  # debug4 = run_cmd("echo", "resolved_module_path = ${local.resolved_module_path}")
}

# Default the stack each deployment deploys based on its directory structure.
# Can be overridden by redefining this block in a child terragrunt.hcl.
terraform {
  source = local.module_source
  extra_arguments "load_config_files" {
    commands           = get_terraform_commands_that_need_vars()
    optional_var_files = local.possible_config_locations
  }
}

remote_state {
  # Use Azure Blob Storage when Vault credentials are available; fall back to local state otherwise.
  backend = local.use_local_state ? "local" : "azurerm"
  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }
  config = local.use_local_state ? {
    path = "${get_repo_root()}/.terraform-state/${local.relative_path}.tfstate"
  } : {
    subscription_id      = lookup(local.vault_state_credentials, "SUBSCRIPTION_ID", "")
    tenant_id            = lookup(local.vault_state_credentials, "TENANT_ID", "")
    client_id            = lookup(local.vault_state_credentials, "CLIENT_ID", "")
    client_secret        = lookup(local.vault_state_credentials, "CLIENT_SECRET", "")
    resource_group_name  = "tf-states"
    storage_account_name = "tfstates"
    container_name       = "terraform-state"
    key                  = local.relative_path
  }
}

inputs = {
  # Used in vault_secret module to compile secret path
  root_deployments_dir      = basename(local.deployments_root_dir)
  root_deployments_dir_path = local.deployments_root_dir
  path_to_repo_root         = get_path_to_repo_root()
  repo_root                 = get_repo_root()
  # Used in vault_secret module to compile secret path
  relative_deployment_path  = local.relative_path
  vault_address             = "${get_env("VAULT_ADDR", "")}"
  vault_token               = "${get_env("VAULT_TOKEN", "")}"
  gitlab_token              = "${get_env("GITLAB_TOKEN", "")}"
  github_owner              = "${get_env("GITHUB_OWNER", "")}"
  github_token              = "${get_env("GITHUB_TOKEN", "")}"

  vault_kv_default_subpath  = local.module_vault_path
}

errors {
    # Retry block for transient errors
    retry "transient_errors" {
        retryable_errors = [".*Error: transient network issue.*"]
        max_attempts = 3
        sleep_interval_sec = 5
    }

    # Ignore block for known safe-to-ignore errors
    ignore "known_safe_errors" {
        ignorable_errors = [
            ".*Error: safe warning.*",
            "!.*Error: do not ignore.*"
        ]
        message = "Ignoring safe warning errors"
        signals = {
            alert_team = false
        }
    }
}

# Configure Terragrunt to download modules to a shared directory outside of the repo to speed up Terraform runs and avoid issues with Git repositories in module paths.
download_dir = "/tmp/.terragrunt-cache"
