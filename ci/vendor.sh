#!/usr/bin/env bash
# Re-vendor the product's IAM permission export into this repo.
#
# The product repo publishes the machine-readable registry at
#   https://api.argusdspm.com/downloads/verification-permissions.json
# and this repo commits a copy at ci/verification-permissions.json so the modules
# can be checked offline and the diff is reviewable in a PR.
#
# Usage:
#   ci/vendor.sh                       # fetch the published export
#   ci/vendor.sh path/to/export.json   # copy a local product-repo export instead
#                                      # (e.g. ../argus/backend/static/downloads/verification-permissions.json)
set -euo pipefail

DEST="$(cd "$(dirname "$0")" && pwd)/verification-permissions.json"
URL="https://api.argusdspm.com/downloads/verification-permissions.json"

if [[ $# -ge 1 ]]; then
  cp "$1" "$DEST"
  echo "vendored from local file: $1"
else
  curl -fsSL "$URL" -o "$DEST"
  echo "vendored from: $URL"
fi
echo "wrote $DEST (version $(python3 -c "import json,sys; print(json.load(open('$DEST'))['version'])"))"
