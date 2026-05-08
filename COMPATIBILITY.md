# Compatibility Matrix

Which version of `deploy-argus` works with which Argus agent image.

| deploy-argus | Argus agent image | Argus backend | Notes |
|---|---|---|---|
| `v0.7.5` | `ghcr.io/argusdspm/argus-agent:stable` (post-Wave 4 Track J) | `https://api.argusdspm.com` | Initial public release. Agent must support `ARGUS_BACKEND_URL` env var; older images that only know `SAAS_API_URL` are not compatible. |

## Pinning

Pin the deploy-argus version in your Terraform module source:

```hcl
source = "github.com/argusdspm/deploy-argus//modules/argus-agent-fargate?ref=v0.7.5"
```

Customers pinned to `v0.7.5` are not affected by changes on `main` or in later tags. To upgrade, change the `?ref=` to the next published tag and run `terraform init -upgrade`.

## Deprecation policy

- Breaking changes only land on a major version bump (`v1.x → v2.0`).
- Pre-v1.0, the contract follows the agent's release cadence; expect minor breaking changes until the v1.0 co-release.
- Each post-v1.0 release line is supported for 12 months after the next major ships.
- Removal of a module variable or output requires one minor-version deprecation cycle (warning in the module + `CHANGELOG.md` notice) before removal.

## Argus image tags

The agent image follows its own release schedule in the main `argus` repo. The `:stable` tag tracks the latest production-supported release; `:vX.Y.Z` tags are immutable. For most customers, `:stable` is the right choice — pin only if you have a specific reason.
