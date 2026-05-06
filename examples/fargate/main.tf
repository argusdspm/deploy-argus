provider "aws" {
  region = var.aws_region
}

module "argus_agent" {
  source = "../../modules/argus-agent-fargate"

  customer_name     = var.customer_name
  enrollment_token  = var.enrollment_token
  argus_backend_url = var.argus_backend_url
  aws_region        = var.aws_region

  vpc_id     = var.vpc_id
  subnet_ids = var.subnet_ids

  enable_s3_scanning = true
  environment        = var.environment
}

output "cluster_name" {
  description = "ECS cluster name."
  value       = module.argus_agent.cluster_name
}

output "baseline_service_name" {
  description = "Baseline ECS service name."
  value       = module.argus_agent.baseline_service_name
}

output "burst_service_name" {
  description = "Burst ECS service name."
  value       = module.argus_agent.burst_service_name
}

output "log_group_name" {
  description = "CloudWatch log group."
  value       = module.argus_agent.log_group_name
}

output "deployment_info" {
  description = "Summary of the deployment."
  value       = module.argus_agent.deployment_info
}
