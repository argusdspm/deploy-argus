# Argus Agent EC2 Deployment Module - Monitoring Configuration
# This file contains CloudWatch monitoring, alarms, and dashboards

# CloudWatch Dashboard for Agent Monitoring
resource "aws_cloudwatch_dashboard" "argus_agent_dashboard" {
  dashboard_name = "ArgusAgent-${var.customer_name}"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6

        properties = {
          metrics = [
            ["AWS/EC2", "CPUUtilization", "InstanceId", aws_instance.argus_agent.id],
            ["AWS/EC2", "NetworkIn", "InstanceId", aws_instance.argus_agent.id],
            ["AWS/EC2", "NetworkOut", "InstanceId", aws_instance.argus_agent.id]
          ]
          view    = "timeSeries"
          stacked = false
          region  = local.aws_region
          title   = "EC2 Instance Metrics"
          period  = 300
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 6

        properties = {
          metrics = [
            ["AWS/EC2", "DiskReadOps", "InstanceId", aws_instance.argus_agent.id],
            ["AWS/EC2", "DiskWriteOps", "InstanceId", aws_instance.argus_agent.id]
          ]
          view    = "timeSeries"
          stacked = false
          region  = local.aws_region
          title   = "Disk I/O Operations"
          period  = 300
        }
      },
      {
        type   = "log"
        x      = 0
        y      = 12
        width  = 24
        height = 6

        properties = {
          query  = "SOURCE '${aws_cloudwatch_log_group.argus_agent_logs.name}' | fields @timestamp, @message | sort @timestamp desc | limit 100"
          region = local.aws_region
          title  = "Recent Agent Logs"
        }
      }
    ]
  })
}

# CloudWatch Alarms for Agent Health Monitoring
resource "aws_cloudwatch_metric_alarm" "agent_instance_health" {
  alarm_name          = "ArgusAgent-InstanceHealth-${var.customer_name}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "StatusCheckFailed"
  namespace           = "AWS/EC2"
  period              = "300"
  statistic           = "Maximum"
  threshold           = "0"
  alarm_description   = "This metric monitors ec2 status check"
  alarm_actions       = [aws_sns_topic.agent_alerts.arn]
  ok_actions          = [aws_sns_topic.agent_alerts.arn]

  dimensions = {
    InstanceId = aws_instance.argus_agent.id
  }

  tags = merge(local.common_tags, {
    Name = "argus-agent-health-${var.customer_name}"
  })
}

resource "aws_cloudwatch_metric_alarm" "agent_cpu_utilization" {
  alarm_name          = "ArgusAgent-HighCPU-${var.customer_name}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "3"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "300"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "This metric monitors ec2 cpu utilization"
  alarm_actions       = [aws_sns_topic.agent_alerts.arn]

  dimensions = {
    InstanceId = aws_instance.argus_agent.id
  }

  tags = merge(local.common_tags, {
    Name = "argus-agent-cpu-${var.customer_name}"
  })
}

resource "aws_cloudwatch_metric_alarm" "agent_memory_utilization" {
  count = var.enable_detailed_monitoring ? 1 : 0

  alarm_name          = "ArgusAgent-HighMemory-${var.customer_name}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "3"
  metric_name         = "MemoryUtilization"
  namespace           = "CWAgent"
  period              = "300"
  statistic           = "Average"
  threshold           = "85"
  alarm_description   = "This metric monitors memory utilization"
  alarm_actions       = [aws_sns_topic.agent_alerts.arn]

  dimensions = {
    InstanceId = aws_instance.argus_agent.id
  }

  tags = merge(local.common_tags, {
    Name = "argus-agent-memory-${var.customer_name}"
  })
}

resource "aws_cloudwatch_metric_alarm" "agent_disk_space" {
  count = var.enable_detailed_monitoring ? 1 : 0

  alarm_name          = "ArgusAgent-LowDiskSpace-${var.customer_name}"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "DiskSpaceUtilization"
  namespace           = "CWAgent"
  period              = "300"
  statistic           = "Average"
  threshold           = "15"
  alarm_description   = "This metric monitors available disk space"
  alarm_actions       = [aws_sns_topic.agent_alerts.arn]

  dimensions = {
    InstanceId = aws_instance.argus_agent.id
    device     = "/dev/xvda1"
    fstype     = "xfs"
    path       = "/"
  }

  tags = merge(local.common_tags, {
    Name = "argus-agent-disk-${var.customer_name}"
  })
}

# Custom CloudWatch Log Metric Filters
resource "aws_cloudwatch_log_metric_filter" "agent_error_count" {
  name           = "ArgusAgent-ErrorCount-${var.customer_name}"
  log_group_name = aws_cloudwatch_log_group.argus_agent_logs.name
  pattern        = "[timestamp, level=\"ERROR\", ...]"

  metric_transformation {
    name      = "AgentErrorCount"
    namespace = "Argus/Agent"
    value     = "1"

    default_value = 0
  }
}

resource "aws_cloudwatch_log_metric_filter" "agent_scan_jobs_completed" {
  name           = "ArgusAgent-ScanJobsCompleted-${var.customer_name}"
  log_group_name = aws_cloudwatch_log_group.argus_agent_logs.name
  pattern        = "[timestamp, level, message=\"Job completed successfully\", ...]"

  metric_transformation {
    name      = "AgentScanJobsCompleted"
    namespace = "Argus/Agent"
    value     = "1"

    default_value = 0
  }
}

resource "aws_cloudwatch_log_metric_filter" "agent_api_errors" {
  name           = "ArgusAgent-APIErrors-${var.customer_name}"
  log_group_name = aws_cloudwatch_log_group.argus_agent_logs.name
  pattern        = "[timestamp, level, message=\"API request failed\" || message=\"Backend communication error\", ...]"

  metric_transformation {
    name      = "AgentAPIErrors"
    namespace = "Argus/Agent"
    value     = "1"

    default_value = 0
  }
}

# Alarms for Custom Metrics
resource "aws_cloudwatch_metric_alarm" "agent_error_rate" {
  alarm_name          = "ArgusAgent-ErrorRate-${var.customer_name}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "AgentErrorCount"
  namespace           = "Argus/Agent"
  period              = "300"
  statistic           = "Sum"
  threshold           = "5"
  alarm_description   = "This metric monitors agent error rate"
  alarm_actions       = [aws_sns_topic.agent_alerts.arn]
  treat_missing_data  = "notBreaching"

  tags = merge(local.common_tags, {
    Name = "argus-agent-error-rate-${var.customer_name}"
  })
}

resource "aws_cloudwatch_metric_alarm" "agent_api_error_rate" {
  alarm_name          = "ArgusAgent-APIErrorRate-${var.customer_name}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "3"
  metric_name         = "AgentAPIErrors"
  namespace           = "Argus/Agent"
  period              = "300"
  statistic           = "Sum"
  threshold           = "3"
  alarm_description   = "This metric monitors agent API communication errors"
  alarm_actions       = [aws_sns_topic.agent_alerts.arn]
  treat_missing_data  = "notBreaching"

  tags = merge(local.common_tags, {
    Name = "argus-agent-api-errors-${var.customer_name}"
  })
}

# SNS Topic for Alerts
resource "aws_sns_topic" "agent_alerts" {
  name         = "argus-agent-alerts-${var.customer_name}"
  display_name = "Argus Agent Alerts for ${var.customer_name}"

  tags = merge(local.common_tags, {
    Name = "argus-agent-alerts-${var.customer_name}"
  })
}

# SNS Topic Policy
resource "aws_sns_topic_policy" "agent_alerts_policy" {
  arn = aws_sns_topic.agent_alerts.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCloudWatchAlarmsToPublish"
        Effect = "Allow"
        Principal = {
          Service = "cloudwatch.amazonaws.com"
        }
        Action   = "SNS:Publish"
        Resource = aws_sns_topic.agent_alerts.arn
      }
    ]
  })
}

# CloudWatch Insights Queries for Agent Analysis
resource "aws_cloudwatch_query_definition" "agent_performance_analysis" {
  name = "Argus Agent Performance Analysis - ${var.customer_name}"

  log_group_names = [aws_cloudwatch_log_group.argus_agent_logs.name]

  query_string = <<EOF
fields @timestamp, @message, level
| filter level = "INFO"
| filter @message like /Job.*completed/
| stats count() by bin(5m)
| sort @timestamp desc
EOF
}

resource "aws_cloudwatch_query_definition" "agent_error_analysis" {
  name = "Argus Agent Error Analysis - ${var.customer_name}"

  log_group_names = [aws_cloudwatch_log_group.argus_agent_logs.name]

  query_string = <<EOF
fields @timestamp, @message, level
| filter level = "ERROR"
| stats count() by @message
| sort count desc
EOF
}

# EventBridge Rule for Agent State Changes
resource "aws_cloudwatch_event_rule" "agent_state_change" {
  name        = "argus-agent-state-change-${var.customer_name}"
  description = "Capture instance state changes for Argus agent"

  event_pattern = jsonencode({
    source      = ["aws.ec2"]
    detail-type = ["EC2 Instance State-change Notification"]
    detail = {
      instance-id = [aws_instance.argus_agent.id]
    }
  })

  tags = local.common_tags
}

# EventBridge Target to SNS
resource "aws_cloudwatch_event_target" "agent_state_change_sns" {
  rule      = aws_cloudwatch_event_rule.agent_state_change.name
  target_id = "ArgusAgentStateChangeSNS"
  arn       = aws_sns_topic.agent_alerts.arn
}