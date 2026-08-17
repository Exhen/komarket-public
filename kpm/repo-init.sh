#!/bin/sh
# Initialise an empty KPM repository (manifest.v2.json).
#
# Usage:
#   ./repo-init.sh [REPO_PATH]
#
# Default REPO_PATH: ../kpm-repo
set -e

KPM="$(cd "$(dirname "$0")" && pwd)"
REPO="${1:-$(cd "${KPM}/.." && pwd)/kpm-repo}"
MANIFEST="${REPO}/manifest.v2.json"

if [ -f "${MANIFEST}" ]; then
    echo "Repository already exists: ${MANIFEST}" >&2
    exit 1
fi

mkdir -p "${REPO}"
cat > "${MANIFEST}" <<'EOF'
{
  "manifest_version": 2,
  "id": "komarket",
  "name": "KOMarket Repository",
  "description": "KOMarket KOReader plugin packages by Exhen.",
  "packages": {}
}
EOF

echo "Created ${MANIFEST}"
echo "Next: ./repo-sync.sh ${REPO}"
