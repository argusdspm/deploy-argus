# Weekly agent refresh - only for the rolling `stable` tag.
#
# A running Fargate task never re-pulls its image, so without this a :stable
# agent would sit at its launch version forever while the dashboard flags it
# as behind. EventBridge Scheduler calls ecs:UpdateService with
# forceNewDeployment=true on the baseline service directly (universal SDK
# target - no Lambda, no agent IAM grant, no agent code); the replacement task
# pulls whatever :stable currently points at. rate(7 days) anchors to resource
# creation time, so a fleet of deploys updates staggered across the week - a
# natural staged rollout.
#
# The burst service needs no schedule: burst tasks are launched fresh on each
# scale-out and pull the current image then. Pinned deploys (any non-stable
# agent_image_tag) never get the updater, by design.
#
# Naming follows the cloud-resource rule: IAM role/policy PascalCase Argus*,
# everything else lowercase argus-*.

resource "aws_iam_role" "agent_refresh_scheduler" {
  count = local.stable_channel ? 1 : 0
  name  = "ArgusAgentScheduler-${var.customer_name}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "scheduler.amazonaws.com"
        }
        Action = "sts:AssumeRole"
        # Confused-deputy guard: only schedules in this account may assume.
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy" "agent_refresh_update_service" {
  count = local.stable_channel ? 1 : 0
  name  = "ArgusAgentSchedulerUpdateService"
  role  = aws_iam_role.agent_refresh_scheduler[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ArgusForceAgentRedeploy"
        Effect   = "Allow"
        Action   = "ecs:UpdateService"
        Resource = "arn:aws:ecs:${local.aws_region}:${data.aws_caller_identity.current.account_id}:service/${aws_ecs_cluster.argus.name}/${aws_ecs_service.baseline.name}"
      }
    ]
  })
}

resource "aws_scheduler_schedule" "agent_refresh" {
  count       = local.stable_channel ? 1 : 0
  name        = "${local.name_prefix}-weekly-refresh"
  description = "Weekly forced deployment so the agent service re-pulls the rolling :stable image."
  state       = "ENABLED"

  schedule_expression = "rate(7 days)"

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = "arn:aws:scheduler:::aws-sdk:ecs:updateService"
    role_arn = aws_iam_role.agent_refresh_scheduler[0].arn

    input = jsonencode({
      Cluster            = aws_ecs_cluster.argus.name
      Service            = aws_ecs_service.baseline.name
      ForceNewDeployment = true
    })
  }
}
