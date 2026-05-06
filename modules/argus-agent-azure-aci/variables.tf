# Variables for the Argus Agent Azure ACI module.
#
# Kept intentionally parallel to terraform/modules/argus-agent-ec2/
# variables.tf — anything that matches across clouds uses the same
# variable name so operators running a multi-cloud deployment don't have
# to translate between two dialects.

# ---------------------------------------------------------------------------
# Required inputs
# ---------------------------------------------------------------------------

variable "customer_name" {
  type        = string
  description = "Short, lowercase identifier for this customer / deployment. Used as a DNS-safe prefix on every resource name."

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,30}[a-z0-9]$", var.customer_name))
    error_message = "customer_name must be 3-32 characters, lowercase alphanumeric + dashes, and start/end with an alphanumeric."
  }
}

variable "enrollment_token" {
  type        = string
  description = "Per cloud-account enrollment token. The agent exchanges it for a per-container API key via POST /agents/bootstrap on first startup. Stored as an ACI secure_environment_variable. Generate at: dashboard → Cloud Accounts → Generate Enrollment Token."
  sensitive   = true

  validation {
    condition     = length(var.enrollment_token) >= 16
    error_message = "enrollment_token looks too short — copy the full token from the dashboard."
  }
}

variable "enrollment_pool" {
  type        = string
  description = "Pool tag passed to the bootstrap endpoint when ENROLLMENT_TOKEN is in use. `baseline` agents are stable anchors; `burst` agents auto-purge after 48h of inactivity."
  default     = "baseline"
  validation {
    condition     = contains(["baseline", "burst"], var.enrollment_pool)
    error_message = "enrollment_pool must be 'baseline' or 'burst'."
  }
}

variable "argus_backend_url" {
  type        = string
  description = "Base URL of the Argus control plane (e.g. https://api.argusdspm.com)."

  validation {
    condition     = can(regex("^https://", var.argus_backend_url))
    error_message = "argus_backend_url must be https:// — the agent refuses to transmit results over plaintext."
  }
}

# ---------------------------------------------------------------------------
# Azure placement
# ---------------------------------------------------------------------------

variable "azure_region" {
  type        = string
  description = "Azure region for the agent resource group + container instance."
  default     = "eastus"
}

# ---------------------------------------------------------------------------
# Optional split-org identity
#
# If your Service Principal already exists (typical when a platform team
# manages identity in one tenant and workloads run elsewhere) provide
# existing_client_id + existing_client_secret + existing_service_principal_id
# and the module skips creating new Azure AD objects.
# ---------------------------------------------------------------------------

variable "existing_client_id" {
  type        = string
  description = "Application (client) ID of a pre-existing Argus Service Principal. Leave null to create one."
  default     = null
}

variable "existing_client_secret" {
  type        = string
  description = "Client secret for the pre-existing Service Principal. Required when existing_client_id is set."
  default     = null
  sensitive   = true
}

variable "existing_service_principal_id" {
  type        = string
  description = "Object ID of the pre-existing Service Principal (not the client ID). Required for role assignment when existing_client_id is set."
  default     = null
}

# ---------------------------------------------------------------------------
# Agent container configuration
# ---------------------------------------------------------------------------

variable "agent_container_image" {
  type        = string
  description = "OCI image reference for the Azure agent. Default tracks the rolling stable tag on GitHub Container Registry (anonymous pulls, no Azure Container Registry auth required)."
  default     = "ghcr.io/argusdspm/argus-agent:stable"
}

variable "agent_log_level" {
  type        = string
  description = "Agent process log level."
  default     = "INFO"

  validation {
    condition     = contains(["DEBUG", "INFO", "WARNING", "ERROR"], var.agent_log_level)
    error_message = "agent_log_level must be one of DEBUG, INFO, WARNING, ERROR."
  }
}

variable "container_cpu" {
  type        = number
  description = "CPU cores allocated to the agent container."
  default     = 1.0
}

variable "container_memory" {
  type        = number
  description = "Memory (GB) allocated to the agent container."
  default     = 2.0
}

variable "environment" {
  type        = string
  description = "Deployment environment label (dev / staging / prod). Surfaces in tags + log streams."
  default     = "prod"
}

# ---------------------------------------------------------------------------
# Networking
# ---------------------------------------------------------------------------

variable "enable_vnet_integration" {
  type        = bool
  description = "Run the container inside a delegated VNet subnet instead of with a public IP. Enables private-link datastore access."
  default     = false
}

variable "vnet_address_space" {
  type        = list(string)
  description = "CIDR range(s) for the VNet created when enable_vnet_integration = true."
  default     = ["10.60.0.0/16"]
}

variable "subnet_address_prefix" {
  type        = string
  description = "CIDR for the delegated ACI subnet."
  default     = "10.60.1.0/24"
}

variable "enable_database_egress" {
  type        = bool
  description = "Open outbound TCP 1433 on the NSG (required for Azure SQL / Synapse scanning with VNet integration)."
  default     = false
}

# ---------------------------------------------------------------------------
# Monitoring
# ---------------------------------------------------------------------------

variable "log_retention_days" {
  type        = number
  description = "Days to retain agent logs in the Log Analytics workspace."
  default     = 30

  validation {
    condition     = var.log_retention_days >= 30 && var.log_retention_days <= 730
    error_message = "Azure Log Analytics requires retention between 30 and 730 days."
  }
}

variable "alert_email" {
  type        = string
  description = "Optional email to notify on container-restart alerts. Leave empty to skip email receivers."
  default     = ""
}

variable "additional_tags" {
  type        = map(string)
  description = "Extra tags merged onto every resource in the module (e.g. cost-centre, team ownership)."
  default     = {}
}

# ---------------------------------------------------------------------------
# Datastore scanning flags
#
# Disabled by default except Blob Storage — operators opt into DB scanning
# explicitly so an agent doesn't start pulling data out of Azure SQL /
# Synapse until they've reviewed the permissions implications.
# ---------------------------------------------------------------------------

variable "enable_blob_scanning" {
  type        = bool
  description = "Let the agent discover + scan Azure Blob Storage containers."
  default     = true
}

variable "enable_azure_sql_scanning" {
  type        = bool
  description = "Let the agent discover + scan Azure SQL databases. Requires per-database credentials configured via the Argus UI."
  default     = false
}

variable "enable_cosmos_db_scanning" {
  type        = bool
  description = "Let the agent discover + scan Azure Cosmos DB accounts (SQL API)."
  default     = false
}

variable "enable_synapse_scanning" {
  type        = bool
  description = "Let the agent discover + scan Synapse SQL pools. Requires per-pool credentials configured via the Argus UI."
  default     = false
}
