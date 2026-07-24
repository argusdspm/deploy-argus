# Argus Agent Fargate Module — Main configuration.
#
# Two ECS services:
#   * argus-agent-baseline — desired_count = 1, never autoscaled. Stable
#     anchor; emits the ArgusDSPM/Agent PendingJobs CloudWatch metric so the
#     burst autoscaler always has a signal even at scale-to-zero.
#   * argus-agent-burst    — desired_count = auto, min=0, max=N. Scales
#     up on pending-jobs depth, drops to 0 when idle.
#
# Both share one enrollment token (per cloud account), stored once as an
# SSM SecureString and injected into both task definitions via `secrets`.

# -----------------------------------------------------------------------------
# Locals
# -----------------------------------------------------------------------------

locals {
  name_prefix = "argus-agent-${var.customer_name}"
  image_uri   = "${var.agent_image_registry}:${var.agent_image_tag}"
  # Region for awslogs + outputs: honor an explicit override, else read from the
  # configured provider so the deploy works in any region (not just us-east-1).
  aws_region = var.aws_region != "" ? var.aws_region : data.aws_region.current.name

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
    # Burst-autoscaler signal. Every agent publishes the total backlog to the
    # same cluster-dimensioned ArgusDSPM/Agent PendingJobs stream that the
    # scale-out/in alarms read (canonical metric contract). Only emitted when
    # autoscaling is on - a baseline-only deploy pays nothing.
    { name = "CLOUDWATCH_METRICS_ENABLED", value = var.enable_burst_autoscaling ? "true" : "false" },
    { name = "CLOUDWATCH_METRICS_CLUSTER", value = local.name_prefix },
  ]
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

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
  count                    = var.enable_burst_autoscaling ? 1 : 0
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
  count           = var.enable_burst_autoscaling ? 1 : 0
  name            = "${local.name_prefix}-burst"
  cluster         = aws_ecs_cluster.argus.arn
  task_definition = aws_ecs_task_definition.burst[0].arn
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
# Burst autoscaler — STEP scaling on the agent-emitted backlog metric.
#
# Canonical metric contract (MUST match the agent's emission exactly, or the
# alarms watch a stream with no data):
#   Namespace  ArgusDSPM/Agent
#   Metric     PendingJobs
#   Dimension  ClusterName = local.name_prefix   (set on the agent via
#              CLOUDWATCH_METRICS_CLUSTER in shared_environment)
#   Value      total unclaimed backlog, Unit=Count, Statistic Average
# The always-on baseline keeps the stream fed even at burst scale-to-zero.
# -----------------------------------------------------------------------------

resource "aws_appautoscaling_target" "burst" {
  count              = var.enable_burst_autoscaling ? 1 : 0
  service_namespace  = "ecs"
  resource_id        = "service/${aws_ecs_cluster.argus.name}/${aws_ecs_service.burst[0].name}"
  scalable_dimension = "ecs:service:DesiredCount"
  min_capacity       = var.burst_min_capacity
  max_capacity       = var.burst_max_capacity
}

resource "aws_appautoscaling_policy" "burst_scale_out" {
  count              = var.enable_burst_autoscaling ? 1 : 0
  name               = "${local.name_prefix}-burst-scale-out"
  policy_type        = "StepScaling"
  service_namespace  = aws_appautoscaling_target.burst[0].service_namespace
  resource_id        = aws_appautoscaling_target.burst[0].resource_id
  scalable_dimension = aws_appautoscaling_target.burst[0].scalable_dimension

  step_scaling_policy_configuration {
    adjustment_type         = "ChangeInCapacity"
    cooldown                = 60
    metric_aggregation_type = "Average"
    step_adjustment {
      metric_interval_lower_bound = 0
      scaling_adjustment          = 1
    }
  }
}

resource "aws_appautoscaling_policy" "burst_scale_in" {
  count              = var.enable_burst_autoscaling ? 1 : 0
  name               = "${local.name_prefix}-burst-scale-in"
  policy_type        = "StepScaling"
  service_namespace  = aws_appautoscaling_target.burst[0].service_namespace
  resource_id        = aws_appautoscaling_target.burst[0].resource_id
  scalable_dimension = aws_appautoscaling_target.burst[0].scalable_dimension

  step_scaling_policy_configuration {
    adjustment_type         = "ChangeInCapacity"
    cooldown                = 300
    metric_aggregation_type = "Average"
    step_adjustment {
      metric_interval_upper_bound = 0
      scaling_adjustment          = -1
    }
  }
}

resource "aws_cloudwatch_metric_alarm" "burst_backlog_high" {
  count               = var.enable_burst_autoscaling ? 1 : 0
  alarm_name          = "${local.name_prefix}-burst-backlog-high"
  alarm_description   = "Unclaimed scan backlog is high - add burst capacity."
  namespace           = "ArgusDSPM/Agent"
  metric_name         = "PendingJobs"
  dimensions          = { ClusterName = local.name_prefix }
  statistic           = "Average"
  period              = 60
  evaluation_periods  = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  threshold           = var.burst_scale_out_backlog
  treat_missing_data  = "notBreaching" # no metric yet = baseline still booting; don't scale
  alarm_actions       = [aws_appautoscaling_policy.burst_scale_out[0].arn]
}

resource "aws_cloudwatch_metric_alarm" "burst_backlog_low" {
  count               = var.enable_burst_autoscaling ? 1 : 0
  alarm_name          = "${local.name_prefix}-burst-backlog-low"
  alarm_description   = "Backlog drained - release burst capacity."
  namespace           = "ArgusDSPM/Agent"
  metric_name         = "PendingJobs"
  dimensions          = { ClusterName = local.name_prefix }
  statistic           = "Average"
  period              = 60
  evaluation_periods  = 3
  comparison_operator = "LessThanThreshold"
  threshold           = var.burst_scale_in_backlog
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_appautoscaling_policy.burst_scale_in[0].arn]
}
