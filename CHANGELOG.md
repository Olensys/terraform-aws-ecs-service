# Changelog

## [1.0.2](https://github.com/Olensys/terraform-aws-ecs-service/compare/v1.0.1...v1.0.2) (2026-10-24)


### Bug Fixes

* **examples:** use the smallest shapes for the integration apply ([6e87116](https://github.com/Olensys/terraform-aws-ecs-service/commit/6e87116953d0e2ee90e2e49624cb7290cbc61f0b))
* run integration on change and weekly instead of nightly ([6501197](https://github.com/Olensys/terraform-aws-ecs-service/commit/65011970e32d00cd7c49ad3537121988f7255ab9))

## 1.0.1

Note: `wait for steady state on every deployment` is a behaviour change that would normally be a minor release; it shipped in 1.0.1.

### Fixes

- render declared provider constraints and skip .terraform in trivy scans
- declare required versions in the example

### Tests

- tags contract, smoke labels, validations and read-only-safe example

### Docs

- reword target group naming notes

### Other

- wait for steady state on every deployment

## 1.0.0

- Initial release: Fargate ECS service wrapping the upstream service module with per-container log groups, scoped execution-role secrets access, optional ALB ingress (target group and listener rule), target-tracking autoscaling, CPU and memory alarms, and an inline task role policy.
