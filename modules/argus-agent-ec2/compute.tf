# Argus Agent EC2 Deployment Module - Compute Resources
# This file contains the EC2 instance and related compute resources

# EC2 Instance for Argus Agent
resource "aws_instance" "argus_agent" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = var.instance_type
  key_name               = var.key_pair_name != "" ? var.key_pair_name : null
  subnet_id              = local.subnet_id
  vpc_security_group_ids = [aws_security_group.argus_agent_sg.id]
  iam_instance_profile   = aws_iam_instance_profile.argus_agent_profile.name
  availability_zone      = local.selected_az

  # Root volume configuration
  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.root_volume_size
    encrypted             = true
    delete_on_termination = true

    tags = merge(local.common_tags, {
      Name = "argus-agent-root-volume-${var.customer_name}"
    })
  }

  # Enhanced monitoring
  monitoring = var.enable_detailed_monitoring

  # User data script for agent setup
  user_data = local.user_data

  # Prevent accidental termination in production
  disable_api_termination = var.environment == "prod" ? true : false

  # Instance metadata service configuration (IMDSv2)
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
    instance_metadata_tags      = "enabled"
  }

  tags = merge(local.common_tags, {
    Name = "argus-agent-${var.customer_name}"
  })

  # Ensure dependencies are created first
  depends_on = [
    aws_iam_instance_profile.argus_agent_profile,
    aws_ssm_parameter.enrollment_token,
    aws_cloudwatch_log_group.argus_agent_logs
  ]

  lifecycle {
    create_before_destroy = true
    ignore_changes = [
      # Ignore AMI changes to prevent unnecessary replacements
      ami
    ]
  }
}

# Elastic IP for stable external access (optional)
resource "aws_eip" "argus_agent_eip" {
  count = var.environment == "prod" ? 1 : 0

  instance = aws_instance.argus_agent.id
  domain   = "vpc"

  tags = merge(local.common_tags, {
    Name = "argus-agent-eip-${var.customer_name}"
  })

  depends_on = [aws_instance.argus_agent]
}

# Auto Scaling Group (optional, for high availability)
resource "aws_launch_template" "argus_agent_template" {
  count = var.auto_scaling_enabled ? 1 : 0

  name_prefix   = "argus-agent-${var.customer_name}-"
  image_id      = data.aws_ami.amazon_linux.id
  instance_type = var.instance_type
  key_name      = var.key_pair_name != "" ? var.key_pair_name : null

  vpc_security_group_ids = [aws_security_group.argus_agent_sg.id]

  iam_instance_profile {
    name = aws_iam_instance_profile.argus_agent_profile.name
  }

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_type           = "gp3"
      volume_size           = var.root_volume_size
      encrypted             = true
      delete_on_termination = true
    }
  }

  monitoring {
    enabled = var.enable_detailed_monitoring
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
    instance_metadata_tags      = "enabled"
  }

  user_data = local.user_data

  tag_specifications {
    resource_type = "instance"
    tags = merge(local.common_tags, {
      Name = "argus-agent-asg-${var.customer_name}"
    })
  }

  tag_specifications {
    resource_type = "volume"
    tags = merge(local.common_tags, {
      Name = "argus-agent-asg-volume-${var.customer_name}"
    })
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Auto Scaling Group
resource "aws_autoscaling_group" "argus_agent_asg" {
  count = var.auto_scaling_enabled ? 1 : 0

  name                      = "argus-agent-asg-${var.customer_name}"
  vpc_zone_identifier       = [local.subnet_id]
  target_group_arns         = []
  health_check_type         = "EC2"
  health_check_grace_period = 300

  min_size         = 1
  max_size         = 2
  desired_capacity = 1

  launch_template {
    id      = aws_launch_template.argus_agent_template[0].id
    version = "$Latest"
  }

  # Instance refresh for rolling updates
  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 50
    }
  }

  tag {
    key                 = "Name"
    value               = "argus-agent-asg-${var.customer_name}"
    propagate_at_launch = true
  }

  dynamic "tag" {
    for_each = local.common_tags
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }

  lifecycle {
    create_before_destroy = true
    ignore_changes        = [desired_capacity]
  }
}

# CloudWatch Alarms for Auto Scaling (if enabled)
resource "aws_cloudwatch_metric_alarm" "agent_cpu_high" {
  count = var.auto_scaling_enabled ? 1 : 0

  alarm_name          = "argus-agent-cpu-high-${var.customer_name}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "300"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "This metric monitors ec2 cpu utilization"
  alarm_actions       = [aws_autoscaling_policy.agent_scale_up[0].arn]

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.argus_agent_asg[0].name
  }

  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "agent_cpu_low" {
  count = var.auto_scaling_enabled ? 1 : 0

  alarm_name          = "argus-agent-cpu-low-${var.customer_name}"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "300"
  statistic           = "Average"
  threshold           = "20"
  alarm_description   = "This metric monitors ec2 cpu utilization"
  alarm_actions       = [aws_autoscaling_policy.agent_scale_down[0].arn]

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.argus_agent_asg[0].name
  }

  tags = local.common_tags
}

# Auto Scaling Policies
resource "aws_autoscaling_policy" "agent_scale_up" {
  count = var.auto_scaling_enabled ? 1 : 0

  name                   = "argus-agent-scale-up-${var.customer_name}"
  scaling_adjustment     = 1
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 300
  autoscaling_group_name = aws_autoscaling_group.argus_agent_asg[0].name
}

resource "aws_autoscaling_policy" "agent_scale_down" {
  count = var.auto_scaling_enabled ? 1 : 0

  name                   = "argus-agent-scale-down-${var.customer_name}"
  scaling_adjustment     = -1
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 300
  autoscaling_group_name = aws_autoscaling_group.argus_agent_asg[0].name
}