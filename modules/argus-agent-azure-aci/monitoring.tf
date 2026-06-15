# Log Analytics workspace + restart alert for the agent container.
#
# The workspace receives container stdout/stderr via the container group's
# diagnostics block (in compute.tf). Alerts fire when the ACI restart
# counter exceeds a threshold, which is how we catch the agent crashing
# in a loop rather than silently staying down.

resource "azurerm_log_analytics_workspace" "argus" {
  name                = "law-${local.name_prefix}"
  location            = azurerm_resource_group.argus.location
  resource_group_name = azurerm_resource_group.argus.name
  sku                 = "PerGB2018"
  retention_in_days   = var.log_retention_days
  tags                = local.common_tags
}

resource "azurerm_monitor_action_group" "argus" {
  name                = "ag-${local.name_prefix}"
  resource_group_name = azurerm_resource_group.argus.name
  short_name          = substr("argus${substr(local.sanitized_name, 0, 6)}", 0, 12)

  dynamic "email_receiver" {
    for_each = var.alert_email != "" ? [1] : []
    content {
      name          = "admin"
      email_address = var.alert_email
    }
  }

  tags = local.common_tags
}

# Container restart alert - fires when the ACI restart counter ticks up
# more than 3 times in 15 minutes. That threshold filters out single
# transient failures (Azure pulls the image, a bad image pull fails once)
# but catches crashloop scenarios within 5 minutes of onset.
resource "azurerm_monitor_metric_alert" "container_restart" {
  name                = "alert-restart-${local.name_prefix}"
  resource_group_name = azurerm_resource_group.argus.name
  scopes              = [azurerm_container_group.argus_agent.id]
  description         = "Argus agent container has restarted repeatedly - check Log Analytics for the root cause."
  frequency           = "PT5M"
  window_size         = "PT15M"
  severity            = 2

  criteria {
    metric_namespace = "Microsoft.ContainerInstance/containerGroups"
    metric_name      = "RestartCount"
    aggregation      = "Total"
    operator         = "GreaterThan"
    threshold        = 3
  }

  action {
    action_group_id = azurerm_monitor_action_group.argus.id
  }

  tags = local.common_tags
}
