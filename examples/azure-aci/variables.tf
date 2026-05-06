variable "customer_name" {
  type        = string
  description = "Short lowercase identifier (3-32 chars, alphanumeric + dashes)."
}

variable "enrollment_token" {
  type        = string
  description = "Argus enrollment token (from dashboard → Cloud Accounts → Generate Enrollment Token)."
  sensitive   = true
}

variable "argus_backend_url" {
  type        = string
  description = "Argus control plane URL (https://...)."
  default     = "https://api.argusdspm.com"
}

variable "azure_region" {
  type        = string
  description = "Azure region for the agent deployment."
  default     = "eastus"
}

variable "environment" {
  type        = string
  description = "Deployment environment (dev/staging/prod)."
  default     = "prod"
}

variable "alert_email" {
  type        = string
  description = "Optional email for container-restart alerts."
  default     = ""
}

variable "enable_azure_sql_scanning" {
  type        = bool
  description = "Let the agent discover + scan Azure SQL databases. Requires per-database credentials configured via the Argus UI once discovery finds them."
  default     = false
}

variable "enable_cosmos_db_scanning" {
  type        = bool
  description = "Let the agent discover + scan Azure Cosmos DB accounts (SQL API)."
  default     = false
}

variable "enable_synapse_scanning" {
  type        = bool
  description = "Let the agent discover + scan Synapse dedicated SQL pools. Requires per-pool SQL credentials configured via the Argus UI."
  default     = false
}
