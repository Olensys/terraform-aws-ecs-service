# Changelog

## [1.1.0](https://github.com/Olensys/terraform-aws-ecs-service/compare/v1.0.3...v1.1.0) (2026-10-25)


### Features

* add runtime options for architecture, spot, storage and filesystem ([#7](https://github.com/Olensys/terraform-aws-ecs-service/issues/7)) ([c602a43](https://github.com/Olensys/terraform-aws-ecs-service/commit/c602a43f76a28ab35208c3e1b31c2aea9a93d9ba))


### Bug Fixes

* **examples:** assign a public IP so tasks can pull the image without NAT ([#4](https://github.com/Olensys/terraform-aws-ecs-service/issues/4)) ([b6978bf](https://github.com/Olensys/terraform-aws-ecs-service/commit/b6978bf23baa7b37933411fae14dfed084818d91))

## [1.0.3](https://github.com/Olensys/terraform-aws-ecs-service/compare/v1.0.2...v1.0.3) (2026-10-24)


### Bug Fixes

* **examples:** unique application slug so concurrent integration runs do not collide ([#2](https://github.com/Olensys/terraform-aws-ecs-service/issues/2)) ([562ece2](https://github.com/Olensys/terraform-aws-ecs-service/commit/562ece227b56bd609535d20cd6d965e5e4f1802a))

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
