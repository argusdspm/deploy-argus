# Argus Agent EC2 Module — Outputs

output "agent_instance_id" {
  description = "EC2 instance ID of the deployed agent."
  value       = aws_instance.argus_agent.id
}

output "agent_instance_arn" {
  description = "ARN of the agent EC2 instance."
  value       = aws_instance.argus_agent.arn
}

output "agent_private_ip" {
  description = "Private IP address of the agent instance."
  value       = aws_instance.argus_agent.private_ip
}

output "agent_public_ip" {
  description = "Public IP address of the agent instance (null if no public IP assigned)."
  value       = aws_instance.argus_agent.public_ip
}

output "agent_availability_zone" {
  description = "Availability zone where the agent is deployed."
  value       = aws_instance.argus_agent.availability_zone
}

output "agent_role_arn" {
  description = "ARN of the IAM role attached to the agent's instance profile."
  value       = aws_iam_role.argus_agent_role.arn
}

output "agent_role_name" {
  description = "Name of the IAM role attached to the agent's instance profile."
  value       = aws_iam_role.argus_agent_role.name
}

output "agent_instance_profile_arn" {
  description = "ARN of the agent's EC2 instance profile."
  value       = aws_iam_instance_profile.argus_agent_profile.arn
}

output "vpc_id" {
  description = "VPC ID where the agent is deployed."
  value       = local.vpc_id
}

output "subnet_id" {
  description = "Subnet ID where the agent is deployed."
  value       = local.subnet_id
}

output "security_group_id" {
  description = "Security group ID for the agent."
  value       = aws_security_group.argus_agent_sg.id
}

output "enrollment_token_param_name" {
  description = "SSM Parameter Store name holding the enrollment token (read by user_data)."
  value       = aws_ssm_parameter.enrollment_token.name
}

output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch log group for agent logs."
  value       = aws_cloudwatch_log_group.argus_agent_logs.name
}

output "cloudwatch_log_group_arn" {
  description = "ARN of the CloudWatch log group for agent logs."
  value       = aws_cloudwatch_log_group.argus_agent_logs.arn
}

output "agent_health_endpoint" {
  description = "Health-check endpoint URL for the agent (internal VPC only)."
  value       = "http://${aws_instance.argus_agent.private_ip}:8080/health"
}

output "customer_name" {
  description = "Customer name used for resource naming."
  value       = var.customer_name
}

output "environment" {
  description = "Environment label for this deployment."
  value       = var.environment
}

output "resource_tags" {
  description = "Common tags applied to all resources."
  value       = local.common_tags
}

output "enabled_datastores" {
  description = "Map of enabled datastore types for scanning."
  value = {
    s3       = local.s3_enabled
    rds      = local.rds_enabled
    dynamodb = local.dynamodb_enabled
    redshift = local.redshift_enabled
  }
}

output "s3_policy_arn" {
  description = "ARN of the S3 IAM policy (null if S3 scanning disabled)."
  value       = local.s3_enabled ? aws_iam_policy.argus_agent_s3_policy[0].arn : null
}

output "rds_policy_arn" {
  description = "ARN of the RDS IAM policy (null if RDS scanning disabled)."
  value       = local.rds_enabled ? aws_iam_policy.argus_agent_rds_policy[0].arn : null
}

output "dynamodb_policy_arn" {
  description = "ARN of the DynamoDB IAM policy (null if DynamoDB scanning disabled)."
  value       = local.dynamodb_enabled ? aws_iam_policy.argus_agent_dynamodb_policy[0].arn : null
}

output "redshift_policy_arn" {
  description = "ARN of the Redshift IAM policy (null if Redshift scanning disabled)."
  value       = local.redshift_enabled ? aws_iam_policy.argus_agent_redshift_policy[0].arn : null
}

output "agent_connection_info" {
  description = "Summary of the deployment for handoff to the Argus dashboard."
  value = {
    instance_id       = aws_instance.argus_agent.id
    role_arn          = aws_iam_role.argus_agent_role.arn
    region            = var.aws_region
    availability_zone = aws_instance.argus_agent.availability_zone
    private_ip        = aws_instance.argus_agent.private_ip
    customer_name     = var.customer_name
    environment       = var.environment
    enabled_datastores = {
      s3       = local.s3_enabled
      rds      = local.rds_enabled
      dynamodb = local.dynamodb_enabled
      redshift = local.redshift_enabled
    }
  }
  sensitive = true
}
