output "id" {
  description = "Identifier (ARN) of the ECS service. Null when create is false."
  value       = var.create ? module.this.id : null
}

output "name" {
  description = "Name of the ECS service. Null when create is false."
  value       = var.create ? var.name : null
}

output "arn" {
  description = "ARN of the ECS service. Null when create is false."
  value       = var.create ? module.this.id : null
}

output "task_definition_arn" {
  description = "ARN of the task definition revision. Null when create is false."
  value       = var.create ? module.this.task_definition_arn : null
}

output "security_group_id" {
  description = "ID of the service security group. Null when create is false."
  value       = var.create ? module.this.security_group_id : null
}

output "target_group_arn" {
  description = "ARN of the load balancer target group. Null when ingress is not set or create is false."
  value       = try(aws_lb_target_group.this[0].arn, null)
}

output "task_role_arn" {
  description = "ARN of the task IAM role. Null when create is false."
  value       = var.create ? module.this.tasks_iam_role_arn : null
}

output "execution_role_arn" {
  description = "ARN of the task execution IAM role. Null when create is false."
  value       = var.create ? module.this.task_exec_iam_role_arn : null
}

output "execution_policy_ssm_parameter_arns" {
  description = "SSM parameter ARNs the execution role may read: exactly the containers' secrets. Null when create is false."
  value       = var.create ? local.execution_policy_ssm_parameter_arns : null
}

output "log_group_names" {
  description = "Map of container name to its CloudWatch log group name. Null when create is false."
  value       = var.create ? local.log_group_names : null
}

output "deployment_circuit_breaker_enabled" {
  description = "Whether the deployment circuit breaker (with rollback) is passed enabled. Null when create is false."
  value       = var.create ? local.deployment_circuit_breaker.enable : null
}

output "tags" {
  description = "Tags applied to every taggable resource, with context.extra_tags merged in. Null when create is false."
  value       = var.create ? local.tags : null
}
