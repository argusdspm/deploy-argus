# Argus Agent Fargate Module - Variables
#
# Self-contained: provisions the ECS cluster, IAM, log group, and SSM
# enrollment-token secret. Customers provide vpc_id + subnet_ids; the
# module wires the rest.

# -----------------------------------------------------------------------------
# Required
# -----------------------------------------------------------------------------

variable "customer_name" {
  type        = string
  description = "Name used for resource naming and tagging (alphanumeric + hyphens)."
  validation {
    condition     = can(regex("^[a-zA-Z0-9-]+$", var.customer_name))
    error_message = "customer_name must contain only alphanumerics and hyphens."
  }
}

variable "enrollment_token" {
  type        = string
  description = "Argus enrollment token. The agent exchanges it for a per-container API key on first start. Generate at: dashboard → Cloud Accounts → Generate Enrollment Token."
  sensitive   = true
  validation {
    condition     = length(var.enrollment_token) >= 16
    error_message = "enrollment_token looks too short - copy the full token from the dashboard."
  }
}

variable "vpc_id" {
  type        = string
  description = "VPC ID where the agent runs."
}

variable "subnet_ids" {
  type        = list(string)
  description = "Subnet IDs for the agent tasks (private recommended; agent only needs outbound HTTPS)."
  validation {
    condition     = length(var.subnet_ids) >= 1
    error_message = "subnet_ids must contain at least one subnet."
  }
}

# -----------------------------------------------------------------------------
# Argus backend
# -----------------------------------------------------------------------------

variable "argus_backend_url" {
  type        = string
  description = "Argus control-plane URL the agent connects to."
  default     = "https://api.argusdspm.com"
  validation {
    condition     = can(regex("^https://", var.argus_backend_url))
    error_message = "argus_backend_url must use HTTPS."
  }
}

variable "agent_image_registry" {
  type        = string
  description = "Public OCI registry the agent is pulled from. Default tracks ghcr.io. Override only for customers mirroring to private registries."
  default     = "ghcr.io/argusdspm/argus-agent"
}

variable "agent_image_tag" {
  type        = string
  description = "Image tag to pin. `stable` follows the rolling release; pin `vX.Y.Z` for reproducible deploys."
  default     = "stable"
}

variable "aws_region" {
  type        = string
  description = "AWS region the ECS cluster runs in. Optional. When null (default), the module reads the region from the configured AWS provider via `data.aws_region.current`. Override only if you need to pin a different region than the provider."
  default     = null
}

# -----------------------------------------------------------------------------
# Sizing
# -----------------------------------------------------------------------------

variable "cpu" {
  type        = number
  description = "Per-task CPU units (Fargate). 1024 = 1 vCPU."
  default     = 1024
}

variable "memory" {
  type        = number
  description = "Per-task memory MiB (Fargate). Must be compatible with cpu - see AWS Fargate pricing/sizing."
  default     = 2048
}

variable "concurrent_jobs" {
  type        = number
  description = "AGENT_CONCURRENT_JOBS env value - bounded ThreadPoolExecutor size in the agent."
  default     = 4
}

variable "burst_min_capacity" {
  type        = number
  description = "Minimum burst tasks. 0 = scale-to-zero (recommended). Baseline service stays at 1 regardless."
  default     = 0
}

variable "burst_max_capacity" {
  type        = number
  description = "Maximum burst tasks the autoscaler may launch."
  default     = 10
}

variable "burst_target_pending_jobs_per_agent" {
  type        = number
  description = "Target pending jobs per active agent. The autoscaler aims to keep this many unclaimed jobs per running burst container."
  default     = 5
}

# -----------------------------------------------------------------------------
# Optional / monitoring
# -----------------------------------------------------------------------------

variable "log_retention_days" {
  type        = number
  description = "CloudWatch log retention period in days."
  default     = 30
  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.log_retention_days)
    error_message = "log_retention_days must be a valid CloudWatch retention period."
  }
}

variable "environment" {
  type        = string
  description = "Environment label (dev/staging/prod) - surfaces in tags."
  default     = "prod"
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}

variable "additional_tags" {
  type        = map(string)
  description = "Additional tags applied to all resources."
  default     = {}
}

# -----------------------------------------------------------------------------
# Datastore scanning opt-ins (mirror EC2 module)
# -----------------------------------------------------------------------------

variable "enable_all_datastores" {
  type        = bool
  description = "Grant scanning permissions for all supported datastore types."
  default     = false
}

variable "enable_s3_scanning" {
  type        = bool
  description = "Enable S3 bucket scanning."
  default     = false
}

variable "enable_rds_scanning" {
  type        = bool
  description = "Enable RDS scanning (MySQL / PostgreSQL / MariaDB)."
  default     = false
}

variable "enable_dynamodb_scanning" {
  type        = bool
  description = "Enable DynamoDB scanning."
  default     = false
}

variable "enable_redshift_scanning" {
  type        = bool
  description = "Enable Redshift scanning (provisioned + Serverless workgroups)."
  default     = false
}

variable "enable_iam_discovery" {
  type        = bool
  description = "Enable IAM discovery - read across users, roles, groups, attached + inline policy documents, MFA devices, access keys, credential reports. Required for §11 Identity & Access in the Argus UI."
  default     = false
}

variable "enable_remediation" {
  type        = bool
  description = "Enable Argus to remediate S3 + IAM misconfigurations. Tenant Settings → Remediation must also be enabled at the application layer."
  default     = false
}

variable "db_secrets_arn_pattern" {
  type        = string
  description = "Secrets Manager ARN pattern for database credentials. Empty disables this permission."
  default     = ""
}

variable "enable_database_egress" {
  type        = bool
  description = "Add security-group egress rules for database ports (3306 / 5432 / 5439)."
  default     = false
}

variable "assign_public_ip" {
  type        = bool
  description = "Whether to assign a public IP to the Fargate task ENI. Set to true when running in a public subnet without a NAT gateway (default-VPC style). Set to false when running in a private subnet that reaches the internet via NAT."
  default     = false
}
