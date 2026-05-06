# Outputs for the Argus Azure ACI module.
#
# The sensitive `agent_connection_info` bundle is the one operators
# actually paste into the Argus dashboard — keeping it as one output
# instead of five means they can't accidentally copy a partial set.

output "resource_group_name" {
  description = "Name of the resource group that holds every resource managed by this module."
  value       = azurerm_resource_group.argus.name
}

output "container_group_id" {
  description = "Full Azure resource ID of the deployed Container Instance."
  value       = azurerm_container_group.argus_agent.id
}

output "container_ip_address" {
  description = "IP address of the container (public when VNet integration is off; private otherwise)."
  value       = azurerm_container_group.argus_agent.ip_address
}

output "log_analytics_workspace_id" {
  description = "Resource ID of the Log Analytics workspace receiving agent logs. Useful for wiring alerts / workbooks outside this module."
  value       = azurerm_log_analytics_workspace.argus.id
}

output "client_id" {
  description = "Application (client) ID of the Service Principal the agent authenticates as."
  value       = local.client_id
}

output "service_principal_id" {
  description = "Object ID of the Service Principal. Not the same as client_id — use this when granting additional Azure RBAC roles."
  value       = local.service_principal_id
}

output "custom_role_id" {
  description = "Resource ID of the custom argus-dspm-scanner role created for this deployment."
  value       = azurerm_role_definition.argus_scanner.role_definition_resource_id
}

# Plaintext secret — only exposed when we created the Service Principal
# ourselves. When binding to an existing SP the secret was supplied by
# the caller and they already have it.
output "client_secret" {
  description = "Client secret for the Service Principal. Emitted once per apply; store it in Argus immediately. Empty when binding to an existing SP."
  value       = local.use_existing_sp ? "" : local.client_secret
  sensitive   = true
}

# Bundled payload for operators to register the agent in Argus.
output "agent_connection_info" {
  description = "Everything the Argus UI's 'Add Cloud Account' flow needs. Treat as sensitive — contains the client secret."
  sensitive   = true
  value = {
    backend_url     = var.argus_backend_url
    cloud_provider  = "azure"
    subscription_id = data.azurerm_subscription.current.subscription_id
    tenant_id       = data.azurerm_client_config.current.tenant_id
    client_id       = local.client_id
    client_secret   = local.use_existing_sp ? "" : local.client_secret
    region          = var.azure_region
  }
}
