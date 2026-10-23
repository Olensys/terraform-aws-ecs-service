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
    image       = string
    port        = optional(number)
    cpu         = optional(number)
    memory      = optional(number)
    essential   = optional(bool, true)
    environment = optional(map(string), {})
    secrets     = optional(map(string), {})
    command     = optional(list(string))
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

variable "desired_count" {
  description = "Desired number of running tasks."
  type        = number
  default     = 1
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
  })
  default = null
  validation {
    condition     = var.ingress == null ? true : (length(coalesce(var.ingress.host_headers, [])) + length(coalesce(var.ingress.path_patterns, []))) > 0
    error_message = "ingress needs at least one of host_headers or path_patterns."
  }
}

variable "autoscaling" {
  description = "Optional target-tracking autoscaling. memory_target adds a memory policy when set."
  type = object({
    min           = number
    max           = number
    cpu_target    = optional(number, 70)
    memory_target = optional(number)
  })
  default = null
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
