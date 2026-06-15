# Argus Agent Fargate Module - Main configuration.
#
# Two ECS services:
#   * argus-agent-baseline - desired_count = 1, never autoscaled. Stable
#     anchor; emits the argus_pending_jobs CloudWatch metric so the burst
#     autoscaler always has a signal even at scale-to-zero.
#   * argus-agent-burst    - desired_count = auto, min=0, max=N. Scales
#     up on pending-jobs depth, drops to 0 when idle.
#
# Both share one enrollment token (per cloud account), stored once as an
# SSM SecureString and injected into both task definitions via `secrets`.

# -----------------------------------------------------------------------------
# Locals
# -----------------------------------------------------------------------------

# Resolve the AWS region from the provider instead of forcing the caller to
# pass it. var.aws_region is still honored if set (back-compat), but defaults
# to the configured provider region. Eliminates the "awslogs-region mismatch"
# class of bug where the module's default us-east-1 silently overrides the
# provider's actual region.
data "aws_region" "current" {}

locals {
  aws_region = coalesce(var.aws_region, data.aws_region.current.name)

  name_prefix = "argus-agent-${var.customer_name}"
  image_uri   = "${var.agent_image_registry}:${var.agent_image_tag}"

  s3_enabled          = var.enable_all_datastores || var.enable_s3_scanning
  rds_enabled         = var.enable_all_datastores || var.enable_rds_scanning
  dynamodb_enabled    = var.enable_all_datastores || var.enable_dynamodb_scanning
  redshift_enabled    = var.enable_all_datastores || var.enable_redshift_scanning
  iam_enabled         = var.enable_iam_discovery
  remediation_enabled = var.enable_remediation

  common_tags = merge({
    Name        = local.name_prefix
    Customer    = var.customer_name
    Environment = var.environment
    Component   = "argus-agent"
    ManagedBy   = "terraform"
    Project     = "argus-dspm"
  }, var.additional_tags)

  shared_environment = [
    { name = "ARGUS_BACKEND_URL", value = var.argus_backend_url },
    { name = "CLOUD_PROVIDER", value = "aws" },
    { name = "AWS_ROLE_ARN", value = "" }, # same-account model
    { name = "AWS_EXTERNAL_ID", value = "" },
    { name = "AGENT_CONCURRENT_JOBS", value = tostring(var.concurrent_jobs) },
  ]
}

data "aws_caller_identity" "current" {}

# -----------------------------------------------------------------------------
# ECS cluster
# -----------------------------------------------------------------------------

resource "aws_ecs_cluster" "argus" {
  name = local.name_prefix

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = local.common_tags
}

# -----------------------------------------------------------------------------
# Logging
# -----------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "argus_agent_logs" {
  name              = "/ecs/${local.name_prefix}"
  retention_in_days = var.log_retention_days

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-logs"
  })
}

# -----------------------------------------------------------------------------
# Enrollment token in SSM Parameter Store
# -----------------------------------------------------------------------------

resource "aws_ssm_parameter" "enrollment_token" {
  name        = "/${local.name_prefix}/enrollment-token"
  description = "Argus enrollment token - exchanged once per task for a per-container API key."
  type        = "SecureString"
  value       = var.enrollment_token
  overwrite   = true

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-enrollment-token"
  })
}

# -----------------------------------------------------------------------------
# Task definitions
# -----------------------------------------------------------------------------

resource "aws_ecs_task_definition" "baseline" {
  family                   = "${local.name_prefix}-baseline"
  cpu                      = var.cpu
  memory                   = var.memory
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.task.arn

  container_definitions = jsonencode([
    {
      name      = "argus-agent"
      image     = local.image_uri
      essential = true
      environment = concat(local.shared_environment, [
        { name = "ENROLLMENT_POOL", value = "baseline" },
      ])
      secrets = [
        { name = "ENROLLMENT_TOKEN", valueFrom = aws_ssm_parameter.enrollment_token.arn },
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.argus_agent_logs.name
          awslogs-region        = local.aws_region
          awslogs-stream-prefix = "baseline"
        }
      }
    },
  ])

  tags = local.common_tags
}

resource "aws_ecs_task_definition" "burst" {
  family                   = "${local.name_prefix}-burst"
  cpu                      = var.cpu
  memory                   = var.memory
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.task.arn

  container_definitions = jsonencode([
    {
      name      = "argus-agent"
      image     = local.image_uri
      essential = true
      environment = concat(local.shared_environment, [
        { name = "ENROLLMENT_POOL", value = "burst" },
      ])
      secrets = [
        { name = "ENROLLMENT_TOKEN", valueFrom = aws_ssm_parameter.enrollment_token.arn },
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.argus_agent_logs.name
          awslogs-region        = local.aws_region
          awslogs-stream-prefix = "burst"
        }
      }
    },
  ])

  tags = local.common_tags
}

# -----------------------------------------------------------------------------
# Services
# -----------------------------------------------------------------------------

resource "aws_ecs_service" "baseline" {
  name            = "${local.name_prefix}-baseline"
  cluster         = aws_ecs_cluster.argus.arn
  task_definition = aws_ecs_task_definition.baseline.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.subnet_ids
    security_groups  = [aws_security_group.argus_agent_sg.id]
    assign_public_ip = var.assign_public_ip
  }

  tags = local.common_tags

  lifecycle {
    ignore_changes = [desired_count]
  }
}

resource "aws_ecs_service" "burst" {
  name            = "${local.name_prefix}-burst"
  cluster         = aws_ecs_cluster.argus.arn
  task_definition = aws_ecs_task_definition.burst.arn
  desired_count   = 0
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.subnet_ids
    security_groups  = [aws_security_group.argus_agent_sg.id]
    assign_public_ip = var.assign_public_ip
  }

  tags = local.common_tags

  lifecycle {
    ignore_changes = [desired_count]
  }
}

# -----------------------------------------------------------------------------
# Burst autoscaler - tracks the agent-emitted argus_pending_jobs metric
# -----------------------------------------------------------------------------

resource "aws_appautoscaling_target" "burst" {
  service_namespace  = "ecs"
  resource_id        = "service/${aws_ecs_cluster.argus.name}/${aws_ecs_service.burst.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  min_capacity       = var.burst_min_capacity
  max_capacity       = var.burst_max_capacity
}

resource "aws_appautoscaling_policy" "burst_scale_on_pending" {
  name               = "${local.name_prefix}-burst-pending-jobs"
  policy_type        = "TargetTrackingScaling"
  service_namespace  = aws_appautoscaling_target.burst.service_namespace
  resource_id        = aws_appautoscaling_target.burst.resource_id
  scalable_dimension = aws_appautoscaling_target.burst.scalable_dimension

  target_tracking_scaling_policy_configuration {
    target_value = var.burst_target_pending_jobs_per_agent
    customized_metric_specification {
      metric_name = "argus_pending_jobs"
      namespace   = "ArgusDSPM/Agent"
      statistic   = "Average"
    }
    scale_in_cooldown  = 300
    scale_out_cooldown = 60
  }
}
