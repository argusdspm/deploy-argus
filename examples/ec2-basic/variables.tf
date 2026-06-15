# Variables for the basic EC2 example.

variable "customer_name" {
  description = "Customer name for resource naming and tagging."
  type        = string
  validation {
    condition     = can(regex("^[a-zA-Z0-9-]+$", var.customer_name))
    error_message = "customer_name must contain only alphanumerics and hyphens."
  }
}

variable "enrollment_token" {
  description = "Argus enrollment token (from dashboard → Cloud Accounts → Generate Enrollment Token)."
  type        = string
  sensitive   = true
  validation {
    condition     = length(var.enrollment_token) >= 16
    error_message = "enrollment_token looks too short - copy the full token from the dashboard."
  }
}

variable "argus_backend_url" {
  description = "Argus control-plane URL."
  type        = string
  default     = "https://api.argusdspm.com"
}

variable "aws_region" {
  description = "AWS region for the deployment."
  type        = string
  default     = "us-east-1"
}

variable "instance_type" {
  description = "EC2 instance type."
  type        = string
  default     = "t3.medium"
}

variable "environment" {
  description = "Environment label (dev/staging/prod)."
  type        = string
  default     = "prod"
}

variable "enable_ssh_access" {
  description = "Enable SSH access for debugging."
  type        = bool
  default     = false
}

variable "allowed_cidr_blocks" {
  description = "CIDR blocks allowed for SSH (required if enable_ssh_access)."
  type        = list(string)
  default     = []
}

variable "key_pair_name" {
  description = "EC2 key pair name for SSH (debugging only)."
  type        = string
  default     = ""
}

variable "enable_s3_scanning" {
  description = "Enable S3 bucket scanning. Most basic deployments turn this on."
  type        = bool
  default     = true
}
