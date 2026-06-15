# Argus Agent Azure Basic Deployment Example
#
# Deploys the Argus DSPM agent as an Azure Container Instance with a
# newly-created Service Principal and subscription-scoped scanner role.
# Suitable for a single-subscription customer whose identity team is
# comfortable with the module creating AD objects on their behalf.

provider "azurerm" {
  features {}
}

provider "azuread" {}

module "argus_agent_azure" {
  source = "../../modules/argus-agent-azure-aci"

  # Required
  customer_name     = var.customer_name
  enrollment_token  = var.enrollment_token
  argus_backend_url = var.argus_backend_url

  azure_region = var.azure_region
  environment  = var.environment

  # Datastore opt-ins - Blob on by default, DBs off unless requested.
  enable_blob_scanning      = true
  enable_azure_sql_scanning = var.enable_azure_sql_scanning
  enable_cosmos_db_scanning = var.enable_cosmos_db_scanning
  enable_synapse_scanning   = var.enable_synapse_scanning

  # Monitoring
  log_retention_days = 30
  alert_email        = var.alert_email

  additional_tags = {
    DeployedBy = "terraform-example"
  }
}

output "resource_group_name" {
  description = "Resource group the agent lives in."
  value       = module.argus_agent_azure.resource_group_name
}

output "container_ip_address" {
  description = "IP address of the agent container."
  value       = module.argus_agent_azure.container_ip_address
}

output "client_id" {
  description = "Service Principal client ID. Paste this into the Argus dashboard."
  value       = module.argus_agent_azure.client_id
}

# The connection bundle contains the client secret, so it's sensitive.
# Retrieve with: terraform output -raw agent_connection_info
output "agent_connection_info" {
  description = "Everything the Argus UI needs to register this agent."
  value       = module.argus_agent_azure.agent_connection_info
  sensitive   = true
}
