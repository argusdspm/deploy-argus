# Argus Agent Azure Container Instance Deployment Module
#
# Provisions everything needed to run the Argus DSPM agent in Azure:
#   - Service Principal (or binds to an existing one for split-org orgs)
#   - Custom least-privilege scanner role + assignment
#   - Container Instance running the argus-agent-azure image
#   - Optional VNet + NSG + subnet delegation for private connectivity
#   - Log Analytics workspace + metric alerts for container health
#
# Azure equivalent of modules/argus-agent-ec2. Keeps shared variable
# names (customer_name, enrollment_token, argus_backend_url) so operators
# moving between clouds don't need to relearn the contract.

terraform {
  required_version = ">= 1.5"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.100"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 2.47"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.11"
    }
  }
}

# Data sources for the current subscription + tenant. The azurerm provider
# is configured at the root module; we read identity attributes here.
data "azurerm_subscription" "current" {}

data "azurerm_client_config" "current" {}

# Local naming + derived values.
locals {
  # Azure resource names are DNS labels in most cases - keep them short
  # and strip anything that isn't alphanumeric or a dash.
  sanitized_name = lower(replace(var.customer_name, "/[^a-zA-Z0-9-]/", "-"))

  name_prefix = "argus-${local.sanitized_name}"

  # When existing_client_id is set we bind to an externally managed
  # Service Principal (common in split-org setups where Argus creates
  # the Service Principal in the identity tenant but deploys compute in
  # a different subscription). Otherwise we create one here.
  use_existing_sp = var.existing_client_id != null && var.existing_client_id != ""

  client_id            = local.use_existing_sp ? var.existing_client_id : azuread_application.argus[0].client_id
  client_secret        = local.use_existing_sp ? var.existing_client_secret : azuread_application_password.argus[0].value
  service_principal_id = local.use_existing_sp ? var.existing_service_principal_id : azuread_service_principal.argus[0].object_id

  # Enabled-datastore flags flow into the agent container as env vars so
  # the agent skips service discovery for anything the customer hasn't
  # opted into.
  enabled_datastores = jsonencode({
    azure_blob    = var.enable_blob_scanning
    azure_sql     = var.enable_azure_sql_scanning
    azure_cosmos  = var.enable_cosmos_db_scanning
    azure_synapse = var.enable_synapse_scanning
  })

  common_tags = merge({
    Name        = local.name_prefix
    Customer    = var.customer_name
    Environment = var.environment
    Component   = "argus-agent"
    ManagedBy   = "terraform"
    Project     = "argus-dspm"
  }, var.additional_tags)

  # Split-org identity: either none of the existing_* inputs are set
  # (module creates the SP) or all three are set (module binds to it).
  # "Partial" combinations would silently create a new SP but try to
  # use a mix of fields, which is always a bug - catch it at plan time.
  existing_sp_inputs_set = [
    var.existing_client_id != null && var.existing_client_id != "",
    var.existing_client_secret != null && var.existing_client_secret != "",
    var.existing_service_principal_id != null && var.existing_service_principal_id != "",
  ]
  existing_sp_set_count = length([for f in local.existing_sp_inputs_set : f if f])
}

# Plan-time validation of the split-org identity contract. Using a
# terraform_data resource with a precondition keeps the error surface
# unambiguous (the failure message appears as its own plan error).
resource "terraform_data" "validate_existing_sp_triplet" {
  lifecycle {
    precondition {
      condition     = local.existing_sp_set_count == 0 || local.existing_sp_set_count == 3
      error_message = "Split-org identity inputs must be all set or all unset. Set existing_client_id, existing_client_secret AND existing_service_principal_id together, or leave all three unset to have the module create a new Service Principal."
    }

    # enable_database_egress has no effect without enable_vnet_integration
    # because the NSG we attach the rule to is only created when VNet
    # integration is on. Silently dropping the rule would leave operators
    # thinking they'd opened up SQL egress when they hadn't.
    precondition {
      condition     = !var.enable_database_egress || var.enable_vnet_integration
      error_message = "enable_database_egress requires enable_vnet_integration=true. Without VNet integration, the ACI container runs on Azure's shared network and the NSG rule is never attached."
    }
  }
}

# Resource group for every resource this module owns - makes uninstall a
# single `terraform destroy` plus a portal cleanup check.
resource "azurerm_resource_group" "argus" {
  name     = "rg-${local.name_prefix}"
  location = var.azure_region
  tags     = local.common_tags
}
