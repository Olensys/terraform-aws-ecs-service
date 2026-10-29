# terraform-aws-ecs-service

Fargate ECS service with task definition, container definitions, scoped IAM, optional ALB ingress, autoscaling and alarms

## Opinions

- Fargate only: `requires_compatibilities` is `FARGATE`, `network_mode` is `awsvpc`, runtime platform is `LINUX` / `X86_64` unless `cpu_architecture` is `ARM64`. Tasks run on plain `FARGATE` unless `capacity_provider_strategy` is set (for example to use `FARGATE_SPOT`).
- Every container has a read-only root filesystem; a container may opt out with `readonly_root_filesystem = false` when it must write to disk, and should prefer a mounted volume.
- One CloudWatch log group per container, named `/ecs/<name>/<container>`, with the container's `log_retention_days`.
- Tags propagate from the service (`propagate_tags = "SERVICE"`); the deployment circuit breaker is on with rollback; task definition changes are not ignored.
- The execution role's SSM statement is scoped to exactly the parameters referenced by container `secrets`, never `*`. Upstream's Logs and ECR statements use `*` as in AWS's managed execution policy.
- Every deployment waits for steady state (`wait_for_steady_state = true`), so a deployment that never stabilises fails the apply, consistent with the circuit breaker and rollback.
- Containers must tolerate a read-only root filesystem (Fargate has no tmpfs); write to mounted volumes instead, or raise `ephemeral_storage_gib` for scratch space.
- `desired_count` applies at creation only; later changes are ignored so autoscaling and deployments own the count.
- The target group name is fixed to `name` (max 32 characters); renaming forces a new one.
- The service security group allows all egress and, when `ingress` is set, inbound traffic only from the load balancer security group on the container port.
- When `ingress` is set the module creates an `ip` target group and a listener rule (host header and/or path pattern conditions). `name` is limited to 32 characters because of the target group.
- Optional target-tracking autoscaling, CPU and memory CloudWatch alarms, and an inline task role policy from `task_role_policy_json`.

## Usage

```hcl
module "naming" {
  source  = "git::https://github.com/Olensys/terraform-null-naming.git?ref=v1.0.1"
  context = var.context
}

module "ecs_service" {
  source  = "git::https://github.com/Olensys/terraform-aws-ecs-service.git?ref=v1.0.1"
  name    = module.naming.name
  context = var.context

  cluster_arn = module.cluster.arn
  network = {
    vpc_id     = "vpc-0123456789abcdef0"
    subnet_ids = ["subnet-0123456789abcdef0", "subnet-0123456789abcdef1"]
  }
  containers = {
    app = {
      image   = "public.ecr.aws/amazonlinux/amazonlinux:2023"
      command = ["sleep", "infinity"]
    }
  }

  tags = module.naming.tags
}
```

## Nightly integration

The nightly apply test runs `examples/minimal` and needs these GitHub repository variables, exported as environment variables:

- `TF_VAR_cluster_arn`: ARN of an existing ECS cluster.
- `TF_VAR_vpc_id`: VPC for the tasks.
- `TF_VAR_subnet_ids`: JSON list string of subnet IDs, for example `["subnet-aaa","subnet-bbb"]`.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.5.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 6.0, < 7.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_aws"></a> [aws](#provider\_aws) | >= 6.0, < 7.0 |

## Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| <a name="module_this"></a> [this](#module\_this) | terraform-aws-modules/ecs/aws//modules/service | 7.6.1 |

## Resources

| Name | Type |
| ---- | ---- |
| [aws_cloudwatch_metric_alarm.cpu](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_metric_alarm) | resource |
| [aws_cloudwatch_metric_alarm.memory](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_metric_alarm) | resource |
| [aws_iam_role_policy.task](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_lb_listener_rule.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_listener_rule) | resource |
| [aws_lb_target_group.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_target_group) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_cluster_arn"></a> [cluster\_arn](#input\_cluster\_arn) | ARN of the ECS cluster the service runs in. | `string` | n/a | yes |
| <a name="input_containers"></a> [containers](#input\_containers) | Containers of the task, keyed by container name. secrets maps environment variable name to an SSM parameter ARN. | <pre>map(object({<br/>    image                    = string<br/>    port                     = optional(number)<br/>    cpu                      = optional(number)<br/>    memory                   = optional(number)<br/>    essential                = optional(bool, true)<br/>    environment              = optional(map(string), {})<br/>    secrets                  = optional(map(string), {})<br/>    command                  = optional(list(string))<br/>    entrypoint               = optional(list(string))<br/>    readonly_root_filesystem = optional(bool, true)<br/>    linux_parameters = optional(object({<br/>      init_process_enabled = optional(bool)<br/>    }))<br/>    health_check = optional(object({<br/>      command      = list(string)<br/>      interval     = optional(number, 30)<br/>      timeout      = optional(number, 5)<br/>      retries      = optional(number, 3)<br/>      start_period = optional(number, 60)<br/>    }))<br/>    log_retention_days = optional(number, 30)<br/>  }))</pre> | n/a | yes |
| <a name="input_context"></a> [context](#input\_context) | Deployment context used for naming, tagging and environment-dependent defaults. | <pre>object({<br/>    organization = string<br/>    environment  = string<br/>    application  = string<br/>    component    = optional(string)<br/>    owner        = string<br/>    cost_center  = string<br/>    extra_tags   = optional(map(string), {})<br/>  })</pre> | n/a | yes |
| <a name="input_name"></a> [name](#input\_name) | Resource name. Lowercase letters, digits and hyphens. | `string` | n/a | yes |
| <a name="input_network"></a> [network](#input\_network) | Network placement: VPC, subnets for the tasks and whether tasks receive a public IP. | <pre>object({<br/>    vpc_id           = string<br/>    subnet_ids       = list(string)<br/>    assign_public_ip = optional(bool, false)<br/>  })</pre> | n/a | yes |
| <a name="input_alarms"></a> [alarms](#input\_alarms) | Optional CPU and memory CloudWatch alarms notifying the given SNS topic. | <pre>object({<br/>    sns_topic_arn    = string<br/>    cpu_threshold    = optional(number, 80)<br/>    memory_threshold = optional(number, 80)<br/>  })</pre> | `null` | no |
| <a name="input_autoscaling"></a> [autoscaling](#input\_autoscaling) | Optional target-tracking autoscaling. memory\_target adds a memory policy when set. | <pre>object({<br/>    min           = number<br/>    max           = number<br/>    cpu_target    = optional(number, 70)<br/>    memory_target = optional(number)<br/>    # Seconds between scaling actions.<br/>    scale_in_cooldown  = optional(number)<br/>    scale_out_cooldown = optional(number)<br/>  })</pre> | `null` | no |
| <a name="input_capacity_provider_strategy"></a> [capacity\_provider\_strategy](#input\_capacity\_provider\_strategy) | Capacity providers to run tasks on, keyed by provider name (FARGATE, FARGATE\_SPOT) with a weight and optional base. Null runs on plain FARGATE. The cluster must have the provider associated (terraform-aws-ecs-cluster associates FARGATE\_SPOT by default). Changing between null and a strategy replaces the service. | <pre>map(object({<br/>    weight = number<br/>    base   = optional(number, 0)<br/>  }))</pre> | `null` | no |
| <a name="input_cpu"></a> [cpu](#input\_cpu) | Task-level CPU units (Fargate sizes: 256, 512, 1024, 2048, 4096, 8192, 16384). | `number` | `512` | no |
| <a name="input_cpu_architecture"></a> [cpu\_architecture](#input\_cpu\_architecture) | CPU architecture of the tasks: X86\_64 (default) or ARM64. The container images must be built for it. | `string` | `"X86_64"` | no |
| <a name="input_create"></a> [create](#input\_create) | Whether to create any resources. Set false to create nothing. | `bool` | `true` | no |
| <a name="input_create_service"></a> [create\_service](#input\_create\_service) | Whether to create the ECS service. Set false to manage only the task definition, roles, log groups and security group, for one-off tasks started with run-task. | `bool` | `true` | no |
| <a name="input_desired_count"></a> [desired\_count](#input\_desired\_count) | Desired number of running tasks. Applies at creation only: later changes are ignored by the underlying service so that autoscaling and deployments own the count. | `number` | `1` | no |
| <a name="input_enable_execute_command"></a> [enable\_execute\_command](#input\_enable\_execute\_command) | Whether to enable ECS Exec on the service. | `bool` | `false` | no |
| <a name="input_ephemeral_storage_gib"></a> [ephemeral\_storage\_gib](#input\_ephemeral\_storage\_gib) | Ephemeral storage per task in GiB (21 to 200). Null keeps the Fargate default of 20 GiB. | `number` | `null` | no |
| <a name="input_ingress"></a> [ingress](#input\_ingress) | Optional ALB ingress: listener to attach a rule to, the ALB security group allowed to reach the tasks, and the routed container. Set at least one of host\_headers or path\_patterns. | <pre>object({<br/>    listener_arn          = string<br/>    alb_security_group_id = string<br/>    container_name        = string<br/>    host_headers          = optional(list(string))<br/>    path_patterns         = optional(list(string))<br/>    priority              = optional(number)<br/>    health_check_path     = optional(string, "/health")<br/>    deregistration_delay  = optional(number, 30)<br/>    # Seconds to ignore failing health checks after a task starts.<br/>    health_check_grace_period = optional(number)<br/>  })</pre> | `null` | no |
| <a name="input_memory"></a> [memory](#input\_memory) | Task-level memory in MiB. | `number` | `1024` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags merged onto every taggable resource, applied last. | `map(string)` | `{}` | no |
| <a name="input_task_role_policy_json"></a> [task\_role\_policy\_json](#input\_task\_role\_policy\_json) | Optional IAM policy document (JSON) attached inline to the task role. | `string` | `null` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_arn"></a> [arn](#output\_arn) | ARN of the ECS service. Null when create or create\_service is false. |
| <a name="output_deployment_circuit_breaker_enabled"></a> [deployment\_circuit\_breaker\_enabled](#output\_deployment\_circuit\_breaker\_enabled) | Whether the deployment circuit breaker (with rollback) is passed enabled. Null when create is false. |
| <a name="output_execution_policy_ssm_parameter_arns"></a> [execution\_policy\_ssm\_parameter\_arns](#output\_execution\_policy\_ssm\_parameter\_arns) | SSM parameter ARNs the execution role may read: exactly the containers' secrets. Null when create is false. |
| <a name="output_execution_role_arn"></a> [execution\_role\_arn](#output\_execution\_role\_arn) | ARN of the task execution IAM role. Null when create is false. |
| <a name="output_id"></a> [id](#output\_id) | Identifier (ARN) of the ECS service. Null when create or create\_service is false. |
| <a name="output_log_group_names"></a> [log\_group\_names](#output\_log\_group\_names) | Map of container name to its CloudWatch log group name. Null when create is false. |
| <a name="output_name"></a> [name](#output\_name) | Name of the ECS service. Null when create or create\_service is false. |
| <a name="output_security_group_id"></a> [security\_group\_id](#output\_security\_group\_id) | ID of the service security group. Null when create is false. |
| <a name="output_tags"></a> [tags](#output\_tags) | Tags applied to every taggable resource, with context.extra\_tags merged in. Null when create is false. |
| <a name="output_target_group_arn"></a> [target\_group\_arn](#output\_target\_group\_arn) | ARN of the load balancer target group. Null when ingress is not set or create is false. |
| <a name="output_task_definition_arn"></a> [task\_definition\_arn](#output\_task\_definition\_arn) | ARN of the task definition revision. Null when create is false. |
| <a name="output_task_role_arn"></a> [task\_role\_arn](#output\_task\_role\_arn) | ARN of the task IAM role. Null when create is false. |
<!-- END_TF_DOCS -->
