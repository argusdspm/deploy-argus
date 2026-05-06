# Changelog

Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versioning: [Semantic Versioning](https://semver.org/).

## [v1.0] — 2026-05-05

Initial public release. Repo rebuilt from scratch from the Argus internal `terraform/` directory; preserves the prior repo state on the `legacy-archive` branch for reference.

### Added
- `modules/argus-agent-ec2` — EC2 module (single-instance, Docker under systemd, public-image pull from `ghcr.io/argusdspm/argus-agent:stable`).
- `modules/argus-agent-fargate` — Fargate module with baseline + autoscaled burst services.
- `modules/argus-agent-azure-aci` — Azure Container Instances module. **Preview**, no UI integration in this release.
- `cloudformation/argus-agent-ec2.yml` — CloudFormation template for one-click EC2 deploy via CFN Quick-Launch.
- `examples/ec2-basic`, `examples/fargate`, `examples/azure-aci` — minimal usage examples for each module.
- `.github/workflows/` — `terraform-validate` (fmt + validate per module) and `cfn-lint` (CloudFormation linting).
- `COMPATIBILITY.md` — deploy-argus ↔ argus version matrix.

### Changed (vs prior repo state on `legacy-archive`)
- Public-registry image (`ghcr.io/argusdspm/argus-agent`) replaces the prior ECR-pull pattern. No customer-side ECR authentication required.
- Environment variable `ARGUS_BACKEND_URL` replaces the legacy `SAAS_API_URL`.
- Repo layout now follows HashiCorp / community conventions: `modules/`, `cloudformation/`, `examples/` at the top level.

### Removed
- `cloudformation/customer-deployment-role.yml` — provider-side cross-account assume-role pattern. Conflicts with the data-sovereignty model (agent runs entirely in customer's account; no inbound provider access).
- `scripts/customer-onboarding.sh` — superseded by the CFN Quick-Launch flow and the in-product Deploy Agent drawer.
- Three legacy validate scripts (`validate-deployment.sh`, `validate-deployment-fixed.sh`, `quick-validate.sh`).
