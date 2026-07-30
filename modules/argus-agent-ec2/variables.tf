# Argus Agent EC2 Module - Variables
#
# v0.7.5 interface: customer provides an enrollment_token (from the Argus
# dashboard); the agent exchanges it on first start for a per-container
# API key. No pre-issued agent_id / agent_api_key plumbing.

# -----------------------------------------------------------------------------
# Required
# -----------------------------------------------------------------------------

variable "customer_name" {
  description = "Name used for resource naming and tagging (alphanumeric + hyphens)."
  type        = string
  validation {
    condition     = can(regex("^[a-zA-Z0-9-]+$", var.customer_name))
    error_message = "customer_name must contain only alphanumerics and hyphens."
  }
}

variable "enrollment_token" {
  description = "Argus enrollment token for this cloud account. Generate at: dashboard → Cloud Accounts → Generate Enrollment Token. Reusable; rotate via the dashboard if leaked."
  type        = string
  sensitive   = true
  validation {
    condition     = length(var.enrollment_token) >= 16
    error_message = "enrollment_token looks too short - copy the full token from the dashboard."
  }
}

# -----------------------------------------------------------------------------
# Argus backend
# -----------------------------------------------------------------------------

variable "argus_backend_url" {
  description = "Argus control-plane URL the agent connects to."
  type        = string
  default     = "https://api.argusdspm.com"
  validation {
    condition     = can(regex("^https://", var.argus_backend_url))
    error_message = "argus_backend_url must use HTTPS."
  }
}

variable "agent_container_image" {
  description = "Public OCI image for the Argus agent. Default tracks the rolling stable tag on GitHub Container Registry. Pin to vX.Y.Z if you need a specific release."
  type        = string
  default     = "ghcr.io/argusdspm/argus-agent:stable"
}

variable "agent_log_level" {
  description = "Agent log level."
  type        = string
  default     = "INFO"
  validation {
    condition     = contains(["DEBUG", "INFO", "WARNING", "ERROR"], var.agent_log_level)
    error_message = "agent_log_level must be one of: DEBUG, INFO, WARNING, ERROR."
  }
}

# -----------------------------------------------------------------------------
# AWS region / network
# -----------------------------------------------------------------------------

variable "aws_region" {
  description = "AWS region for agent deployment. Leave empty to read from the configured provider."
  type        = string
  default     = ""
}

variable "availability_zone" {
  description = "Availability zone for the EC2 instance (optional; first AZ in region used if empty)."
  type        = string
  default     = ""
}

variable "vpc_id" {
  description = "VPC ID for agent deployment. If empty, the module creates a new VPC."
  type        = string
  default     = ""
}

variable "subnet_id" {
  description = "Subnet ID for agent deployment. If empty, the module creates one in the (existing or new) VPC."
  type        = string
  default     = ""
}

variable "allowed_cidr_blocks" {
  description = "CIDR blocks allowed for SSH access (debugging only - empty in production)."
  type        = list(string)
  default     = []
}

# -----------------------------------------------------------------------------
# EC2 instance
# -----------------------------------------------------------------------------

variable "instance_type" {
  description = "EC2 instance type."
  type        = string
  default     = "t3.medium"
  validation {
    condition     = contains(["t3.small", "t3.medium", "t3.large", "t3.xlarge", "c5.large", "c5.xlarge"], var.instance_type)
    error_message = "instance_type must be one of: t3.small, t3.medium, t3.large, t3.xlarge, c5.large, c5.xlarge."
  }
}

variable "key_pair_name" {
  description = "EC2 key pair name for SSH (debugging only)."
  type        = string
  default     = ""
}

variable "root_volume_size" {
  description = "Root volume size in GB."
  type        = number
  default     = 20
  validation {
    condition     = var.root_volume_size >= 20 && var.root_volume_size <= 100
    error_message = "root_volume_size must be between 20 and 100 GB."
  }
}

variable "enable_ssh_access" {
  description = "Enable SSH access for debugging (not recommended in production). Opens port 22 from the region's EC2 Instance Connect prefix list, and additionally from allowed_cidr_blocks when that is set. Leave false and use AWS Systems Manager Session Manager, which needs no open port."
  type        = bool
  default     = false
}

variable "enable_health_endpoint" {
  description = "Open the agent health endpoint (port 8080) to the VPC CIDR. Off by default: the agent polls outbound and needs no inbound reachability to function, so this is only useful if you scrape the endpoint from inside the VPC."
  type        = bool
  default     = false
}

variable "enable_detailed_monitoring" {
  description = "Enable detailed CloudWatch monitoring on the EC2 instance."
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "CloudWatch log retention period in days."
  type        = number
  default     = 30
  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.log_retention_days)
    error_message = "log_retention_days must be a valid CloudWatch retention period."
  }
}

variable "environment" {
  description = "Environment label (dev/staging/prod). Production also disables instance termination."
  type        = string
  default     = "prod"
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}

variable "auto_scaling_enabled" {
  description = "Enable Auto Scaling Group (creates a launch template + ASG instead of a single instance). Most customers should use the argus-agent-fargate module for elastic scaling instead."
  type        = bool
  default     = false
}

variable "backup_enabled" {
  description = "Enable automated backups (no-op placeholder; reserved for future)."
  type        = bool
  default     = true
}

variable "additional_tags" {
  description = "Additional tags applied to all resources."
  type        = map(string)
  default     = {}
}

# -----------------------------------------------------------------------------
# Datastore scanning opt-ins
# -----------------------------------------------------------------------------

variable "enable_all_datastores" {
  description = "Grant scanning permissions for all supported datastore types. Overrides individual enable_* flags when true."
  type        = bool
  default     = false
}

variable "enable_s3_scanning" {
  description = "Enable S3 bucket scanning. Grants discovery + read on all S3 buckets in the account."
  type        = bool
  default     = false
}

variable "enable_rds_scanning" {
  description = "Enable RDS scanning (MySQL / PostgreSQL / MariaDB). Grants discovery + IAM DB Auth."
  type        = bool
  default     = false
}

variable "enable_dynamodb_scanning" {
  description = "Enable DynamoDB scanning. Grants discovery + read on all tables."
  type        = bool
  default     = false
}

variable "enable_redshift_scanning" {
  description = "Enable Redshift scanning. Grants discovery + Data API access on all clusters (provisioned and Serverless)."
  type        = bool
  default     = false
}

variable "enable_iam_discovery" {
  description = "Enable IAM discovery. Grants read across users, roles, groups, attached + inline policy documents, MFA devices, access keys, and credential reports. Required for §11 Identity & Access in the Argus UI."
  type        = bool
  default     = false
}

variable "enable_remediation" {
  description = "Enable Argus to remediate S3 + IAM misconfigurations (block public access, enforce encryption, restrict bucket policy, enable versioning, disable stale access keys, remove over-privileged policies, enforce MFA). Tenant Settings → Remediation must also be enabled at the application layer."
  type        = bool
  default     = false
}

variable "db_secrets_arn_pattern" {
  description = "Secrets Manager ARN pattern for database credentials (e.g. 'arn:aws:secretsmanager:*:*:secret:argus/*'). Empty disables this permission entirely."
  type        = string
  default     = ""
}

variable "enable_database_egress" {
  description = "Add security-group egress rules for database ports (3306 / 5432 / 5439)."
  type        = bool
  default     = false
}

variable "database_egress_cidr_blocks" {
  description = "CIDR blocks for database egress. Empty defaults to the VPC CIDR."
  type        = list(string)
  default     = []
}

variable "health_check_interval" {
  description = "Agent health-check interval in seconds (informational; passed to the agent via env)."
  type        = number
  default     = 30
  validation {
    condition     = var.health_check_interval >= 10 && var.health_check_interval <= 300
    error_message = "health_check_interval must be between 10 and 300 seconds."
  }
}
