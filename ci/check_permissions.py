#!/usr/bin/env python3
"""deploy-argus IAM contract check against the product's permission registry.

The product repo (argus_agent/core/verification_permissions.py) is the single
source of truth for WHICH IAM permission each posture signal needs. It publishes
a machine-readable export at
    https://api.argusdspm.com/downloads/verification-permissions.json
and this repo commits a VENDORED copy at ci/verification-permissions.json.

The Terraform modules here are a deliberately RICHER superset of that set (they
add Redshift Data API, IAM DB auth, credential retrieval, policy simulation, and
tighter per-service ARN scoping). So this is a CONTRACT check, not a regenerator:
it never rewrites the .tf. It enforces one invariant - the modules grant at least
every REQUIRED action - and flags when the vendored copy has fallen behind the
product's published registry.

Three checks:
  1. completeness  - every required action (from the vendored export) is granted
                     somewhere in each AWS module's IAM. Extras are allowed.
  2. forbidden     - no non-existent IAM action that grants nothing while looking
                     like coverage (e.g. s3:GetBucketEncryption).
  3. staleness     - the vendored copy matches the product's PUBLISHED export.
                     Soft-skips when the URL is unreachable (e.g. before the
                     product side has deployed) so it never reds main on a network
                     blip; fails only on a definitive content mismatch.

    python3 ci/check_permissions.py            # completeness + forbidden + staleness
    python3 ci/check_permissions.py --offline  # skip the network staleness check
"""
from __future__ import annotations

import argparse
import json
import re
import sys
import urllib.error
import urllib.request
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
VENDORED = REPO / "ci/verification-permissions.json"
PUBLISHED_URL = "https://api.argusdspm.com/downloads/verification-permissions.json"

# AWS modules whose IAM must cover the required set. Azure is a separate surface
# and is not governed by the AWS registry.
MODULE_IAM = {
    "argus-agent-fargate": REPO / "modules/argus-agent-fargate/security.tf",
    "argus-agent-ec2": REPO / "modules/argus-agent-ec2/security.tf",
}

# Non-existent actions that read as coverage while granting nothing. Kept in
# lock-step with FORBIDDEN_ACTIONS in the product's test_iam_policy_contract.py.
FORBIDDEN_ACTIONS = {
    "s3:GetBucketEncryption": "not a real action; use s3:GetEncryptionConfiguration",
    "s3:DeletePublicAccessBlock": "not a real action; uses s3:PutBucketPublicAccessBlock",
    "s3:DeleteBucketEncryption": "not a real action; uses s3:PutEncryptionConfiguration",
}

_ACTION_RE = re.compile(r"""['"]([a-z0-9-]+:[A-Za-z][A-Za-z]*)['"]""")
FIX = "run ci/vendor.sh to re-vendor, and add any listed action to the module security.tf"


def _required(export: dict) -> set[str]:
    groups = list(export.get("signals", {}).values()) + list(export.get("remediation", {}).values())
    return {a for perms in groups for a in perms}


def _actions_in_tf(path: Path) -> set[str]:
    # HCL comments start with '#' or '//'; drop them so a documented action never
    # counts as granted.
    lines = []
    for line in path.read_text(encoding="utf-8").splitlines():
        s = line.strip()
        if s.startswith("#") or s.startswith("//"):
            continue
        lines.append(line)
    return set(_ACTION_RE.findall("\n".join(lines)))


def _fetch(url: str) -> dict | None:
    try:
        with urllib.request.urlopen(url, timeout=15) as resp:  # noqa: S310 (fixed https URL)
            if resp.status != 200:
                return None
            return json.loads(resp.read().decode("utf-8"))
    except (urllib.error.URLError, OSError, ValueError):
        return None


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--offline", action="store_true", help="skip the network staleness check")
    args = ap.parse_args()

    if not VENDORED.exists():
        print(f"FAIL: vendored export missing at {VENDORED.relative_to(REPO)}. Run ci/vendor.sh.", file=sys.stderr)
        return 1
    export = json.loads(VENDORED.read_text(encoding="utf-8"))
    required = _required(export)
    failures: list[str] = []

    # 1 + 2: completeness + forbidden, per module.
    for name, tf in MODULE_IAM.items():
        actions = _actions_in_tf(tf)
        missing = sorted(required - actions)
        if missing:
            failures.append(
                f"{name}: missing {len(missing)} required action(s): {', '.join(missing)}"
            )
        bad = sorted(a for a in FORBIDDEN_ACTIONS if a in actions)
        if bad:
            failures.append(
                f"{name}: grants non-existent action(s): "
                + ", ".join(f"{a} ({FORBIDDEN_ACTIONS[a]})" for a in bad)
            )

    # 3: staleness (soft-skip when unreachable).
    if args.offline:
        print("staleness: skipped (--offline)")
    else:
        published = _fetch(PUBLISHED_URL)
        if published is None:
            print(f"staleness: SKIPPED - {PUBLISHED_URL} unreachable (product side may not be deployed yet).")
        elif published != export:
            pub_v, ven_v = published.get("version"), export.get("version")
            rel = "ahead of" if pub_v != ven_v else "different from"
            failures.append(
                f"vendored export is STALE: the published registry (version {pub_v}) is {rel} "
                f"the vendored copy (version {ven_v}). Re-vendor with ci/vendor.sh."
            )
        else:
            print(f"staleness: OK (vendored matches published, version {export.get('version')})")

    if failures:
        print("\nIAM contract check FAILED:", file=sys.stderr)
        for f in failures:
            print(f"  - {f}", file=sys.stderr)
        print(f"\nFix: {FIX}", file=sys.stderr)
        return 1

    print(f"IAM contract check passed: both AWS modules grant all {len(required)} required actions.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
