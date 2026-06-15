# Argus Agent - basic EC2 deployment example.

provider "aws" {
  region = var.aws_region
}

module "argus_agent_ec2" {
  source = "../../modules/argus-agent-ec2"

  customer_name     = var.customer_name
  enrollment_token  = var.enrollment_token
  argus_backend_url = var.argus_backend_url
  aws_region        = var.aws_region

  instance_type = var.instance_type
  environment   = var.environment

  enable_ssh_access   = var.enable_ssh_access
  allowed_cidr_blocks = var.allowed_cidr_blocks
  key_pair_name       = var.key_pair_name

  enable_detailed_monitoring = true
  log_retention_days         = 30

  enable_s3_scanning = var.enable_s3_scanning

  additional_tags = {
    DeployedBy = "terraform-example"
  }
}

output "agent_instance_id" {
  description = "EC2 instance ID of the deployed agent."
  value       = module.argus_agent_ec2.agent_instance_id
}

output "agent_role_arn" {
  description = "ARN of the agent's IAM role."
  value       = module.argus_agent_ec2.agent_role_arn
}

output "agent_private_ip" {
  description = "Private IP address of the agent instance."
  value       = module.argus_agent_ec2.agent_private_ip
}

output "cloudwatch_log_group_name" {
  description = "CloudWatch log group name."
  value       = module.argus_agent_ec2.cloudwatch_log_group_name
}

output "enrollment_token_param_name" {
  description = "SSM Parameter Store name where the enrollment token is stored."
  value       = module.argus_agent_ec2.enrollment_token_param_name
}
