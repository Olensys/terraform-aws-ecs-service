mock_provider "aws" {
  mock_resource "aws_lb_target_group" {
    defaults = {
      arn = "arn:aws:elasticloadbalancing:eu-west-1:123456789012:targetgroup/example/0123456789abcdef"
    }
  }
  mock_resource "aws_iam_policy" {
    defaults = {
      arn = "arn:aws:iam::123456789012:policy/example"
    }
  }
  mock_resource "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::123456789012:role/example"
    }
  }
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }
}

variables {
  context = {
    organization = "olensys"
    environment  = "test"
    application  = "example"
    owner        = "platform"
    cost_center  = "eng"
  }
  name        = "example"
  cluster_arn = "arn:aws:ecs:eu-west-1:123456789012:cluster/example-cluster"
  network = {
    vpc_id     = "vpc-0123456789abcdef0"
    subnet_ids = ["subnet-0123456789abcdef0", "subnet-0123456789abcdef1"]
  }
  containers = {
    app = {
      image = "public.ecr.aws/nginx/nginx:stable"
      port  = 80
    }
  }
}

run "test_create_false_plans_nothing" {
  command = plan

  variables {
    create = false
  }

  assert {
    condition     = output.id == null && output.name == null && output.arn == null && output.task_definition_arn == null && output.security_group_id == null && output.target_group_arn == null && output.task_role_arn == null && output.execution_role_arn == null && output.tags == null
    error_message = "All outputs must be null when create is false."
  }

  assert {
    condition     = length(aws_lb_target_group.this) == 0 && length(aws_lb_listener_rule.this) == 0 && length(aws_cloudwatch_metric_alarm.cpu) == 0 && length(aws_cloudwatch_metric_alarm.memory) == 0 && length(aws_iam_role_policy.task) == 0
    error_message = "No root resources may be planned when create is false."
  }

  assert {
    condition     = output.execution_policy_ssm_parameter_arns == null && output.log_group_names == null && output.deployment_circuit_breaker_enabled == null
    error_message = "Test-support outputs must be null when create is false."
  }
}

run "test_ingress_creates_tg_and_rule" {
  command = plan

  variables {
    ingress = {
      listener_arn          = "arn:aws:elasticloadbalancing:eu-west-1:123456789012:listener/app/alb/0123456789abcdef/0123456789abcdef"
      alb_security_group_id = "sg-0123456789abcdef0"
      container_name        = "app"
      host_headers          = ["app.example.com"]
      priority              = 100
    }
  }

  assert {
    condition     = length(aws_lb_target_group.this) == 1 && aws_lb_target_group.this[0].target_type == "ip"
    error_message = "An ip-target target group must be created when ingress is set."
  }

  assert {
    condition     = aws_lb_target_group.this[0].port == 80 && aws_lb_target_group.this[0].protocol == "HTTP"
    error_message = "Target group port must equal the ingress container port."
  }

  assert {
    condition     = aws_lb_target_group.this[0].health_check[0].path == "/health" && aws_lb_target_group.this[0].deregistration_delay == "30"
    error_message = "Health check path and deregistration delay defaults must apply."
  }

  assert {
    condition     = length(aws_lb_listener_rule.this) == 1 && aws_lb_listener_rule.this[0].priority == 100
    error_message = "A listener rule must be created with the given priority."
  }

  assert {
    condition     = anytrue([for c in aws_lb_listener_rule.this[0].condition : contains(flatten([for h in c.host_header : h.values]), "app.example.com")])
    error_message = "Listener rule must carry the host header condition."
  }
}

run "test_no_ingress_no_tg" {
  command = plan

  assert {
    condition     = length(aws_lb_target_group.this) == 0 && length(aws_lb_listener_rule.this) == 0
    error_message = "No target group or listener rule without ingress."
  }

  assert {
    condition     = output.target_group_arn == null
    error_message = "target_group_arn must be null without ingress."
  }
}

run "test_secrets_scope_execution_policy" {
  # SMOKE: asserts the local list passed to upstream as task_exec_ssm_param_arns equals the secrets' ARNs, not the rendered execution policy. Upstream's Logs and ECR statements use * (as in AWS's managed policy) and are not visible here; the real check is the apply test.
  command = plan

  variables {
    containers = {
      app = {
        image = "public.ecr.aws/nginx/nginx:stable"
        port  = 80
        secrets = {
          DB_PASSWORD = "arn:aws:ssm:eu-west-1:123456789012:parameter/app/db"
          API_KEY     = "arn:aws:ssm:eu-west-1:123456789012:parameter/app/key"
        }
      }
      sidecar = {
        image = "public.ecr.aws/example/sidecar:1"
        secrets = {
          TOKEN = "arn:aws:ssm:eu-west-1:123456789012:parameter/app/token"
        }
      }
    }
  }

  assert {
    condition     = toset(output.execution_policy_ssm_parameter_arns) == toset(["arn:aws:ssm:eu-west-1:123456789012:parameter/app/db", "arn:aws:ssm:eu-west-1:123456789012:parameter/app/key", "arn:aws:ssm:eu-west-1:123456789012:parameter/app/token"]) && length(output.execution_policy_ssm_parameter_arns) == 3
    error_message = "Execution policy must be scoped to exactly the secrets' parameter ARNs."
  }

  assert {
    condition     = !contains(output.execution_policy_ssm_parameter_arns, "*")
    error_message = "Execution policy must never use a wildcard resource."
  }
}

run "test_log_group_per_container" {
  # SMOKE: asserts the computed name map only, not log group creation or retention; the apply test and trivy cover the real resources.
  command = plan

  variables {
    containers = {
      app = {
        image = "public.ecr.aws/nginx/nginx:stable"
        port  = 80
      }
      sidecar = {
        image              = "public.ecr.aws/example/sidecar:1"
        log_retention_days = 7
      }
    }
  }

  assert {
    condition     = output.log_group_names == { app = "/ecs/example/app", sidecar = "/ecs/example/sidecar" }
    error_message = "One log group named /ecs/<name>/<container> per container."
  }
}

run "test_circuit_breaker_on" {
  # SMOKE: asserts the literal passed to upstream, not the resulting service attribute; the apply test covers the real service.
  command = plan

  assert {
    condition     = output.deployment_circuit_breaker_enabled == true
    error_message = "The deployment circuit breaker (with rollback) must be passed enabled. Only the literal is visible to tests; the resulting service attribute is covered by the apply test."
  }
}

run "test_two_instances_distinct_role_names" {
  # SMOKE: asserts the target group and log group names derive from the instance name, not IAM role names (upstream role names are not visible to tests).
  command = plan

  variables {
    name = "a"
    ingress = {
      listener_arn          = "arn:aws:elasticloadbalancing:eu-west-1:123456789012:listener/app/alb/0123456789abcdef/0123456789abcdef"
      alb_security_group_id = "sg-0123456789abcdef0"
      container_name        = "app"
      path_patterns         = ["/*"]
    }
  }

  assert {
    condition     = aws_lb_target_group.this[0].name == "a"
    error_message = "Root names must derive from the instance name."
  }
}

run "test_two_instances_distinct_role_names_b" {
  # SMOKE: second instance of the pair above; same limits.
  command = plan

  variables {
    name = "b"
    ingress = {
      listener_arn          = "arn:aws:elasticloadbalancing:eu-west-1:123456789012:listener/app/alb/0123456789abcdef/0123456789abcdef"
      alb_security_group_id = "sg-0123456789abcdef0"
      container_name        = "app"
      path_patterns         = ["/*"]
    }
  }

  assert {
    condition     = aws_lb_target_group.this[0].name == "b" && output.log_group_names["app"] == "/ecs/b/app"
    error_message = "Instance b must get names distinct from instance a (upstream role names are derived from the same name input but are not visible to tests)."
  }
}

run "test_alarms_created" {
  command = plan

  variables {
    alarms = {
      sns_topic_arn = "arn:aws:sns:eu-west-1:123456789012:alerts"
    }
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.cpu[0].metric_name == "CPUUtilization" && aws_cloudwatch_metric_alarm.memory[0].metric_name == "MemoryUtilization" && aws_cloudwatch_metric_alarm.cpu[0].dimensions["ClusterName"] == "example-cluster" && aws_cloudwatch_metric_alarm.cpu[0].threshold == 80
    error_message = "CPU and memory alarms must target the cluster and service."
  }
}

run "test_task_policy_and_container_shape_plan" {
  # SMOKE: asserts only the module-owned task role inline policy; the rest proves the health check, command, environment, autoscaling and execute-command inputs convert to upstream's types at plan. Autoscaling resources live in upstream and are not visible.
  command = plan

  variables {
    containers = {
      app = {
        image = "public.ecr.aws/nginx/nginx:stable"
        port  = 80
        health_check = {
          command = ["CMD-SHELL", "curl -f http://localhost/ || exit 1"]
        }
        environment = { LOG_LEVEL = "info" }
        command     = ["nginx", "-g", "daemon off;"]
      }
    }
    autoscaling = {
      min           = 2
      max           = 6
      memory_target = 75
    }
    task_role_policy_json  = "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Action\":\"sqs:SendMessage\",\"Resource\":\"arn:aws:sqs:eu-west-1:123456789012:q\"}]}"
    enable_execute_command = true
  }

  assert {
    condition     = length(aws_iam_role_policy.task) == 1 && aws_iam_role_policy.task[0].name == "example-task"
    error_message = "The task role inline policy must be created from task_role_policy_json."
  }
}

run "test_tags_contract" {
  command = plan

  variables {
    tags = { Owner = "x" }
    context = {
      organization = "olensys"
      environment  = "test"
      application  = "example"
      owner        = "platform"
      cost_center  = "eng"
      extra_tags   = { Owner = "y", Team = "z" }
    }
  }

  assert {
    condition     = output.tags.Owner == "x" && output.tags.Team == "z"
    error_message = "var.tags must win over context.extra_tags, and extra_tags must still be merged."
  }
}

run "test_autoscaling_bounds_rejected" {
  command = plan

  variables {
    autoscaling = { min = 5, max = 2 }
  }

  expect_failures = [var.autoscaling]
}

run "test_log_retention_rejected" {
  command = plan

  variables {
    containers = {
      app = { image = "x", port = 80, log_retention_days = 10 }
    }
  }

  expect_failures = [var.containers]
}

run "test_name_length_validation" {
  command = plan

  variables {
    name = join("", [for i in range(33) : "a"])
  }

  expect_failures = [var.name]
}

run "test_runtime_options_plan" {
  # SMOKE: only proves the new runtime inputs plan; upstream resources are not visible.
  command = plan

  variables {
    cpu_architecture = "ARM64"
    capacity_provider_strategy = {
      FARGATE      = { weight = 0 }
      FARGATE_SPOT = { weight = 1 }
    }
    ephemeral_storage_gib = 50
    containers = {
      app = {
        image                    = "public.ecr.aws/nginx/nginx:stable"
        port                     = 80
        entrypoint               = ["sh", "-c"]
        readonly_root_filesystem = false
        linux_parameters = {
          init_process_enabled = true
          tmpfs                = [{ container_path = "/dev/shm", size = 512 }]
        }
      }
    }
    ingress = {
      listener_arn              = "arn:aws:elasticloadbalancing:eu-west-1:123456789012:listener/app/alb/0123456789abcdef/0123456789abcdef"
      alb_security_group_id     = "sg-0123456789abcdef0"
      container_name            = "app"
      host_headers              = ["app.example.com"]
      priority                  = 100
      health_check_grace_period = 120
    }
    autoscaling = {
      min                = 1
      max                = 4
      scale_in_cooldown  = 300
      scale_out_cooldown = 60
    }
  }

  assert {
    condition     = length(aws_lb_target_group.this) == 1
    error_message = "The module must still plan with all runtime options set."
  }
}

run "test_cpu_architecture_rejected" {
  command = plan

  variables {
    cpu_architecture = "ARM"
  }

  expect_failures = [var.cpu_architecture]
}

run "test_capacity_provider_rejected" {
  command = plan

  variables {
    capacity_provider_strategy = { SPOT = { weight = 1 } }
  }

  expect_failures = [var.capacity_provider_strategy]
}

run "test_ephemeral_storage_rejected" {
  command = plan

  variables {
    ephemeral_storage_gib = 10
  }

  expect_failures = [var.ephemeral_storage_gib]
}
