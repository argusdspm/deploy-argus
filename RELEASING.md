# Releasing deploy-argus

`deploy-argus` is versioned **independently of the Argus agent** (see the
Versioning policy in [`CHANGELOG.md`](CHANGELOG.md)). This repo re-releases only
when the Terraform/CloudFormation modules change; the agent image versions on its
own schedule in the main `argus` repo. Their numbers are not required to match.

## When to cut a release

Cut a new tag when `main` has any customer-visible module change since the last
tag:

- a new, renamed, removed, or default-changed module **variable** or **output**
- new **resources**, a new **module**, or a new **provider**
- a **networking or IAM** change customers will apply
- a **permission re-vendor** (`ci/verification-permissions.json`) that changes the
  actions the modules grant

Do **not** cut a release for:

- an agent code release (that tags `agent-v*` in the main repo)
- internal refactors, comments, or formatting with no interface change - those
  ride the next release

## Classify the bump

Per the Versioning policy, by **module-interface impact**:

- **Major (`X.0.0`)** - breaking: a variable renamed/removed, a module deleted;
  the customer must edit their Terraform.
- **Minor (`x.Y.0`)** - backward-compatible additions: new optional
  variables/outputs, a new module/provider, new opt-in behavior.
- **Patch (`x.y.Z`)** - docs, default tweaks, internal refactors, or a re-vendor
  that does not change granted actions.

When in doubt, bump minor.

## Steps

1. **Green main.** Confirm the `permissions-check`, `terraform-validate`, and
   `fmt` checks pass on `main`.
2. **CHANGELOG.md.** Rename `## [Unreleased]` to `## [vX.Y.Z] - YYYY-MM-DD` and
   add a fresh empty `## [Unreleased]` above it. Lead the section with a one-line
   summary (and the agent image it co-releases with, if any).
3. **COMPATIBILITY.md.** Add a row: the new tag, the agent image it was verified
   against, the backend, and upgrade notes (resource replacement? new vars?
   breaking?).
4. **Commit** as `release: vX.Y.Z` and push to `main`.
5. **Tag and push:** `git tag vX.Y.Z && git push origin vX.Y.Z`.
6. **GitHub Release:** `gh release create vX.Y.Z --title "vX.Y.Z" --notes "<the
   CHANGELOG section>"`.
7. **Point the product at it** (main `argus` repo): set `DEPLOY_REPO_REF` in
   `frontend/src/config/deployment.ts` to the new tag, then run `make permissions`
   to regenerate the `?ref=` in the DIY-Terraform docs. Commit.

Managed one-click customers are unaffected by a deploy-argus release - their
CloudFormation templates ship from the product's S3, not from a deploy-argus tag.
Only DIY-Terraform customers pin `?ref=`, and they upgrade by moving that ref.
