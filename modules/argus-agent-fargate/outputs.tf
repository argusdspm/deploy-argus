# Argus Agent Fargate Module - Outputs

output "cluster_name" {
  description = "Name of the ECS cluster created for the agent."
  value       = aws_ecs_cluster.argus.name
}

output "cluster_arn" {
  description = "ARN of the ECS cluster."
  value       = aws_ecs_cluster.argus.arn
}

output "baseline_service_name" {
  description = "Name of the always-on baseline ECS service."
  value       = aws_ecs_service.baseline.name
}

output "burst_service_name" {
  description = "Name of the autoscaled burst ECS service."
  value       = aws_ecs_service.burst.name
}

output "baseline_task_definition_arn" {
  description = "ARN of the baseline task definition."
  value       = aws_ecs_task_definition.baseline.arn
}

output "burst_task_definition_arn" {
  description = "ARN of the burst task definition."
  value       = aws_ecs_task_definition.burst.arn
}

output "execution_role_arn" {
  description = "ARN of the ECS task execution role."
  value       = aws_iam_role.execution.arn
}

output "task_role_arn" {
  description = "ARN of the ECS task role (the agent process runs under this)."
  value       = aws_iam_role.task.arn
}

output "security_group_id" {
  description = "Security group ID attached to both services."
  value       = aws_security_group.argus_agent_sg.id
}

output "enrollment_token_param_name" {
  description = "SSM Parameter Store name holding the enrollment token."
  value       = aws_ssm_parameter.enrollment_token.name
}

output "log_group_name" {
  description = "CloudWatch log group receiving agent logs."
  value       = aws_cloudwatch_log_group.argus_agent_logs.name
}

output "enabled_datastores" {
  description = "Map of enabled datastore types."
  value = {
    s3       = local.s3_enabled
    rds      = local.rds_enabled
    dynamodb = local.dynamodb_enabled
    redshift = local.redshift_enabled
  }
}

output "deployment_info" {
  description = "Summary of the deployment for handoff to the Argus dashboard."
  value = {
    customer    = var.customer_name
    region      = local.aws_region
    environment = var.environment
    cpu         = var.cpu
    memory      = var.memory
    cluster     = aws_ecs_cluster.argus.name
    burst_max   = var.burst_max_capacity
  }
}
