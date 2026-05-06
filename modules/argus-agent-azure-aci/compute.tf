# Azure Container Instance running the Argus agent.
#
# One container, one group — ACI groups are mostly useful for sidecars and
# we don't need any. The agent polls the Argus control plane for work, so
# it needs outbound HTTPS but no inbound. We still publish :8080 for the
# container's own /health probe (even though nothing external hits it)
# because Azure requires at least one port declared for the liveness_probe
# to work.

resource "azurerm_container_group" "argus_agent" {
  name                = "aci-${local.name_prefix}"
  location            = azurerm_resource_group.argus.location
  resource_group_name = azurerm_resource_group.argus.name
  os_type             = "Linux"
  restart_policy      = "Always"

  # Private VNet integration requires subnet_ids instead of public
  # ip_address_type. When not integrated we default to a public IP so
  # the container can reach the Argus control plane over the open
  # internet (HTTPS only, pinned via argus_backend_url validation).
  ip_address_type = var.enable_vnet_integration ? "Private" : "Public"
  subnet_ids      = var.enable_vnet_integration ? [azurerm_subnet.argus_aci[0].id] : null

  container {
    name   = "argus-agent"
    image  = var.agent_container_image
    cpu    = var.container_cpu
    memory = var.container_memory

    ports {
      port     = 8080
      protocol = "TCP"
    }

    # Non-secret configuration — safe to expose via Azure Monitor /
    # portal. Secrets go in secure_environment_variables below.
    # Wave 4 Track J: ARGUS_BACKEND_URL replaces the legacy SAAS_API_URL,
    # AGENT_ID is removed (the agent self-identifies via /agents/me),
    # and ENROLLMENT_POOL is set so the bootstrap path can place the
    # row in the right pool.
    environment_variables = {
      CLOUD_PROVIDER        = "azure"
      ARGUS_BACKEND_URL     = var.argus_backend_url
      ENROLLMENT_POOL       = var.enrollment_pool
      AZURE_SUBSCRIPTION_ID = data.azurerm_subscription.current.subscription_id
      AZURE_TENANT_ID       = data.azurerm_client_config.current.tenant_id
      AZURE_CLIENT_ID       = local.client_id
      LOG_LEVEL             = var.agent_log_level
      ENABLED_DATASTORES    = local.enabled_datastores
    }

    # Secure env vars are never returned via the control-plane APIs and
    # are masked in the portal. The agent reads ENROLLMENT_TOKEN at first
    # start and exchanges it for a per-container API key via
    # POST /agents/bootstrap.
    secure_environment_variables = {
      AZURE_CLIENT_SECRET = local.client_secret
      ENROLLMENT_TOKEN    = var.enrollment_token
    }

    # Fail-fast liveness probe. Longer period (30s) than the Argus poll
    # interval (10s) so a single slow poll doesn't trigger a restart.
    liveness_probe {
      http_get {
        path   = "/health"
        port   = 8080
        scheme = "Http"
      }
      initial_delay_seconds = 30
      period_seconds        = 30
      timeout_seconds       = 10
      failure_threshold     = 3
    }
  }

  # Send container stdout/stderr to Log Analytics so operators can tail
  # the agent's output without jumping into the Azure portal every time.
  diagnostics {
    log_analytics {
      workspace_id  = azurerm_log_analytics_workspace.argus.workspace_id
      workspace_key = azurerm_log_analytics_workspace.argus.primary_shared_key
      log_type      = "ContainerInsights"
    }
  }

  tags = local.common_tags

  # Role assignment must land before the container starts or its first
  # token request will 403. azurerm builds these in parallel by default.
  depends_on = [
    azurerm_role_assignment.argus_scanner,
  ]
}
