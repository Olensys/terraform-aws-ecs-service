variable "name" {
  description = "Resource name. Lowercase letters, digits and hyphens."
  type        = string
  validation {
    condition     = can(regex("^[a-z0-9-]{1,32}$", var.name))
    error_message = "name must match ^[a-z0-9-]{1,32}$."
  }
}

variable "context" {
  description = "Deployment context used for naming, tagging and environment-dependent defaults."
  type = object({
    organization = string
    environment  = string
    application  = string
    component    = optional(string)
    owner        = string
    cost_center  = string
    extra_tags   = optional(map(string), {})
  })
  validation {
    condition     = contains(["dev", "staging", "prod", "test", "shared"], var.context.environment)
    error_message = "context.environment must be one of dev, staging, prod, test, shared."
  }
}

variable "create" {
  description = "Whether to create any resources. Set false to create nothing."
  type        = bool
  default     = true
}

variable "cluster_arn" {
  description = "ARN of the ECS cluster the service runs in."
  type        = string
}

variable "containers" {
  description = "Containers of the task, keyed by container name. secrets maps environment variable name to an SSM parameter ARN."
  type = map(object({
    image                    = string
    port                     = optional(number)
    cpu                      = optional(number)
    memory                   = optional(number)
    essential                = optional(bool, true)
    environment              = optional(map(string), {})
    secrets                  = optional(map(string), {})
    command                  = optional(list(string))
    entrypoint               = optional(list(string))
    readonly_root_filesystem = optional(bool, true)
    linux_parameters = optional(object({
      init_process_enabled = optional(bool)
    }))
    health_check = optional(object({
      command      = list(string)
      interval     = optional(number, 30)
      timeout      = optional(number, 5)
      retries      = optional(number, 3)
      start_period = optional(number, 60)
    }))
    log_retention_days = optional(number, 30)
  }))
  validation {
    condition     = length(var.containers) > 0
    error_message = "containers must define at least one container."
  }
  validation {
    condition = alltrue([for c in var.containers : contains(
      [0, 1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653],
    c.log_retention_days)])
    error_message = "containers[*].log_retention_days must be a value CloudWatch Logs accepts (0, 1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288 or 3653)."
  }
}

variable "cpu" {
  description = "Task-level CPU units (Fargate sizes: 256, 512, 1024, 2048, 4096, 8192, 16384)."
  type        = number
  default     = 512
}

variable "memory" {
  description = "Task-level memory in MiB."
  type        = number
  default     = 1024
}

variable "cpu_architecture" {
  description = "CPU architecture of the tasks: X86_64 (default) or ARM64. The container images must be built for it."
  type        = string
  default     = "X86_64"
  validation {
    condition     = contains(["X86_64", "ARM64"], var.cpu_architecture)
    error_message = "cpu_architecture must be X86_64 or ARM64."
  }
}

variable "capacity_provider_strategy" {
  description = "Capacity providers to run tasks on, keyed by provider name (FARGATE, FARGATE_SPOT) with a weight and optional base. Null runs on plain FARGATE. The cluster must have the provider associated (terraform-aws-ecs-cluster associates FARGATE_SPOT by default). Changing between null and a strategy replaces the service."
  type = map(object({
    weight = number
    base   = optional(number, 0)
  }))
  default = null
  validation {
    condition     = var.capacity_provider_strategy == null ? true : alltrue([for k in keys(var.capacity_provider_strategy) : contains(["FARGATE", "FARGATE_SPOT"], k)])
    error_message = "capacity_provider_strategy keys must be FARGATE or FARGATE_SPOT."
  }
}

variable "ephemeral_storage_gib" {
  description = "Ephemeral storage per task in GiB (21 to 200). Null keeps the Fargate default of 20 GiB."
  type        = number
  default     = null
  validation {
    condition     = var.ephemeral_storage_gib == null ? true : (var.ephemeral_storage_gib >= 21 && var.ephemeral_storage_gib <= 200)
    error_message = "ephemeral_storage_gib must be between 21 and 200 when set."
  }
}

variable "desired_count" {
  description = "Desired number of running tasks. Applies at creation only: later changes are ignored by the underlying service so that autoscaling and deployments own the count."
  type        = number
  default     = 1
  validation {
    condition     = var.desired_count >= 0
    error_message = "desired_count must be zero or greater."
  }
}

variable "network" {
  description = "Network placement: VPC, subnets for the tasks and whether tasks receive a public IP."
  type = object({
    vpc_id           = string
    subnet_ids       = list(string)
    assign_public_ip = optional(bool, false)
  })
}

variable "ingress" {
  description = "Optional ALB ingress: listener to attach a rule to, the ALB security group allowed to reach the tasks, and the routed container. Set at least one of host_headers or path_patterns."
  type = object({
    listener_arn          = string
    alb_security_group_id = string
    container_name        = string
    host_headers          = optional(list(string))
    path_patterns         = optional(list(string))
    priority              = optional(number)
    health_check_path     = optional(string, "/health")
    deregistration_delay  = optional(number, 30)
    # Seconds to ignore failing health checks after a task starts.
    health_check_grace_period = optional(number)
  })
  default = null
  validation {
    condition     = var.ingress == null ? true : (length(coalesce(var.ingress.host_headers, [])) + length(coalesce(var.ingress.path_patterns, []))) > 0
    error_message = "ingress needs at least one of host_headers or path_patterns."
  }
  validation {
    condition     = var.ingress == null ? true : (var.ingress.priority == null ? true : (var.ingress.priority >= 1 && var.ingress.priority <= 50000))
    error_message = "ingress.priority must be between 1 and 50000 when set."
  }
}

variable "autoscaling" {
  description = "Optional target-tracking autoscaling. memory_target adds a memory policy when set."
  type = object({
    min           = number
    max           = number
    cpu_target    = optional(number, 70)
    memory_target = optional(number)
    # Seconds between scaling actions.
    scale_in_cooldown  = optional(number)
    scale_out_cooldown = optional(number)
  })
  default = null
  validation {
    condition     = var.autoscaling == null ? true : (var.autoscaling.min <= var.autoscaling.max && var.autoscaling.min >= 0)
    error_message = "autoscaling.min must be zero or greater and not exceed autoscaling.max."
  }
  validation {
    condition = var.autoscaling == null ? true : (
      var.autoscaling.cpu_target >= 1 && var.autoscaling.cpu_target <= 100 &&
    (var.autoscaling.memory_target == null ? true : (var.autoscaling.memory_target >= 1 && var.autoscaling.memory_target <= 100)))
    error_message = "autoscaling.cpu_target and autoscaling.memory_target must be between 1 and 100."
  }
}

variable "alarms" {
  description = "Optional CPU and memory CloudWatch alarms notifying the given SNS topic."
  type = object({
    sns_topic_arn    = string
    cpu_threshold    = optional(number, 80)
    memory_threshold = optional(number, 80)
  })
  default = null
}

variable "task_role_policy_json" {
  description = "Optional IAM policy document (JSON) attached inline to the task role."
  type        = string
  default     = null
}

variable "enable_execute_command" {
  description = "Whether to enable ECS Exec on the service."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags merged onto every taggable resource, applied last."
  type        = map(string)
  default     = {}
}
