locals {
  tags = merge(var.context.extra_tags, var.tags)

  cluster_name = var.create ? element(split("/", var.cluster_arn), 1) : null

  ingress_enabled = var.create && var.ingress != null
  ingress_port    = var.ingress == null ? null : try(var.containers[var.ingress.container_name].port, null)

  execution_policy_ssm_parameter_arns = distinct(flatten([for c in var.containers : values(c.secrets)]))

  deployment_circuit_breaker = { enable = true, rollback = true }

  log_group_names = { for k, _ in var.containers : k => "/ecs/${var.name}/${k}" }

  container_definitions = {
    for k, c in var.containers : k => {
      image                  = c.image
      cpu                    = c.cpu
      memory                 = c.memory
      essential              = c.essential
      command                = c.command
      entrypoint             = c.entrypoint
      readonlyRootFilesystem = c.readonly_root_filesystem
      linuxParameters = {
        initProcessEnabled = try(c.linux_parameters.init_process_enabled, null)
        tmpfs = length(try(c.linux_parameters.tmpfs, [])) == 0 ? null : [for t in c.linux_parameters.tmpfs : {
          containerPath = t.container_path
          size          = t.size
          mountOptions  = t.mount_options
        }]
      }
      environment = [for n, v in c.environment : { name = n, value = v }]
      secrets     = [for n, v in c.secrets : { name = n, valueFrom = v }]
      portMappings = c.port == null ? [] : [{
        name          = k
        containerPort = c.port
        protocol      = "tcp"
      }]
      healthCheck = c.health_check == null ? null : {
        command     = c.health_check.command
        interval    = c.health_check.interval
        timeout     = c.health_check.timeout
        retries     = c.health_check.retries
        startPeriod = c.health_check.start_period
      }
      enable_cloudwatch_logging              = true
      create_cloudwatch_log_group            = true
      cloudwatch_log_group_name              = local.log_group_names[k]
      cloudwatch_log_group_use_name_prefix   = false
      cloudwatch_log_group_retention_in_days = c.log_retention_days
    }
  }

  autoscaling_policies = var.autoscaling == null ? {} : merge(
    {
      cpu = {
        policy_type = "TargetTrackingScaling"
        target_tracking_scaling_policy_configuration = {
          target_value       = var.autoscaling.cpu_target
          scale_in_cooldown  = var.autoscaling.scale_in_cooldown
          scale_out_cooldown = var.autoscaling.scale_out_cooldown
          predefined_metric_specification = {
            predefined_metric_type = "ECSServiceAverageCPUUtilization"
          }
        }
      }
    },
    var.autoscaling.memory_target == null ? {} : {
      memory = {
        policy_type = "TargetTrackingScaling"
        target_tracking_scaling_policy_configuration = {
          target_value       = var.autoscaling.memory_target
          scale_in_cooldown  = var.autoscaling.scale_in_cooldown
          scale_out_cooldown = var.autoscaling.scale_out_cooldown
          predefined_metric_specification = {
            predefined_metric_type = "ECSServiceAverageMemoryUtilization"
          }
        }
      }
    },
  )
}

resource "aws_lb_target_group" "this" {
  count = local.ingress_enabled ? 1 : 0

  # The name is fixed to var.name (max 32 characters); changing it forces a new target group.
  name                 = var.name
  vpc_id               = var.network.vpc_id
  target_type          = "ip"
  protocol             = "HTTP"
  port                 = local.ingress_port
  deregistration_delay = var.ingress.deregistration_delay

  health_check {
    path     = var.ingress.health_check_path
    protocol = "HTTP"
    matcher  = "200-399"
  }

  tags = local.tags

  lifecycle {
    precondition {
      condition     = local.ingress_port != null
      error_message = "ingress.container_name must name a container that defines a port."
    }
  }
}

resource "aws_lb_listener_rule" "this" {
  count = local.ingress_enabled ? 1 : 0

  listener_arn = var.ingress.listener_arn
  priority     = var.ingress.priority

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this[0].arn
  }

  dynamic "condition" {
    for_each = length(coalesce(var.ingress.host_headers, [])) > 0 ? [1] : []
    content {
      host_header {
        values = var.ingress.host_headers
      }
    }
  }

  dynamic "condition" {
    for_each = length(coalesce(var.ingress.path_patterns, [])) > 0 ? [1] : []
    content {
      path_pattern {
        values = var.ingress.path_patterns
      }
    }
  }

  tags = local.tags
}

module "this" {
  source  = "terraform-aws-modules/ecs/aws//modules/service"
  version = "7.6.1"

  create = var.create
  name   = var.name

  cluster_arn   = var.cluster_arn
  cpu           = var.cpu
  memory        = var.memory
  desired_count = var.desired_count

  launch_type              = var.capacity_provider_strategy == null ? "FARGATE" : null
  requires_compatibilities = ["FARGATE"]
  capacity_provider_strategy = var.capacity_provider_strategy == null ? null : {
    for k, s in var.capacity_provider_strategy : k => {
      capacity_provider = k
      weight            = s.weight
      base              = s.base
    }
  }
  network_mode = "awsvpc"
  runtime_platform = {
    operating_system_family = "LINUX"
    cpu_architecture        = var.cpu_architecture
  }

  ephemeral_storage = var.ephemeral_storage_gib == null ? null : {
    size_in_gib = var.ephemeral_storage_gib
  }
  health_check_grace_period_seconds = local.ingress_enabled ? var.ingress.health_check_grace_period : null

  container_definitions = local.container_definitions

  subnet_ids       = var.network.subnet_ids
  assign_public_ip = var.network.assign_public_ip
  vpc_id           = var.network.vpc_id

  create_security_group = true
  security_group_ingress_rules = var.ingress == null ? {} : {
    alb = {
      description                  = "Container port from the load balancer"
      referenced_security_group_id = var.ingress.alb_security_group_id
      from_port                    = local.ingress_port
      to_port                      = local.ingress_port
      ip_protocol                  = "tcp"
    }
  }
  security_group_egress_rules = {
    all = {
      description = "All outbound traffic"
      ip_protocol = "-1"
      cidr_ipv4   = "0.0.0.0/0"
    }
  }

  load_balancer = local.ingress_enabled ? {
    service = {
      target_group_arn = aws_lb_target_group.this[0].arn
      container_name   = var.ingress.container_name
      container_port   = local.ingress_port
    }
  } : {}

  enable_autoscaling       = var.autoscaling != null
  autoscaling_min_capacity = var.autoscaling == null ? 1 : var.autoscaling.min
  autoscaling_max_capacity = var.autoscaling == null ? 10 : var.autoscaling.max
  autoscaling_policies     = local.autoscaling_policies

  deployment_circuit_breaker     = local.deployment_circuit_breaker
  propagate_tags                 = "SERVICE"
  ignore_task_definition_changes = false
  enable_execute_command         = var.enable_execute_command
  wait_for_steady_state          = true

  # Execution role: secrets access scoped to exactly the referenced parameters.
  task_exec_ssm_param_arns = local.execution_policy_ssm_parameter_arns
  task_exec_secret_arns    = []

  tags = local.tags
}

resource "aws_iam_role_policy" "task" {
  count = var.create && var.task_role_policy_json != null ? 1 : 0

  name   = "${var.name}-task"
  role   = module.this.tasks_iam_role_name
  policy = var.task_role_policy_json
}

resource "aws_cloudwatch_metric_alarm" "cpu" {
  count = var.create && var.alarms != null ? 1 : 0

  alarm_name          = "${var.name}-cpu-high"
  alarm_description   = "CPU utilization of ECS service ${var.name} is above ${var.alarms.cpu_threshold}%"
  namespace           = "AWS/ECS"
  metric_name         = "CPUUtilization"
  statistic           = "Average"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  threshold           = var.alarms.cpu_threshold
  period              = 300
  evaluation_periods  = 2
  alarm_actions       = [var.alarms.sns_topic_arn]

  dimensions = {
    ClusterName = local.cluster_name
    ServiceName = var.name
  }

  tags = local.tags
}

resource "aws_cloudwatch_metric_alarm" "memory" {
  count = var.create && var.alarms != null ? 1 : 0

  alarm_name          = "${var.name}-memory-high"
  alarm_description   = "Memory utilization of ECS service ${var.name} is above ${var.alarms.memory_threshold}%"
  namespace           = "AWS/ECS"
  metric_name         = "MemoryUtilization"
  statistic           = "Average"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  threshold           = var.alarms.memory_threshold
  period              = 300
  evaluation_periods  = 2
  alarm_actions       = [var.alarms.sns_topic_arn]

  dimensions = {
    ClusterName = local.cluster_name
    ServiceName = var.name
  }

  tags = local.tags
}
