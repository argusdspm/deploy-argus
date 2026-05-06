variable "customer_name" {
  description = "Customer name for resource naming and tagging."
  type        = string
}

variable "enrollment_token" {
  description = "Argus enrollment token (from dashboard → Cloud Accounts → Generate Enrollment Token)."
  type        = string
  sensitive   = true
}

variable "argus_backend_url" {
  description = "Argus control-plane URL."
  type        = string
  default     = "https://api.argusdspm.com"
}

variable "aws_region" {
  description = "AWS region for deployment."
  type        = string
  default     = "us-east-1"
}

variable "vpc_id" {
  description = "VPC ID where the agent will run."
  type        = string
}

variable "subnet_ids" {
  description = "Subnet IDs for the Fargate tasks (private subnets recommended)."
  type        = list(string)
}

variable "environment" {
  description = "Environment label (dev/staging/prod)."
  type        = string
  default     = "prod"
}
