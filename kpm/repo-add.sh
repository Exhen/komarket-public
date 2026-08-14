#!/bin/sh
# Add built komarket .kpkg artifacts to a KPM repository manifest (manifest.v2.json).
#
# Usage:
#   ./repo-add.sh [REPO_PATH]
#
# REPO_PATH defaults to ../kindlemodding-repo (sibling clone of KindleModding/repo).
# Clone first if missing:
#   git clone https://github.com/KindleModding/repo.git ../kindlemodding-repo
set -e

KPM="$(cd "$(dirname "$0")" && pwd)"
DIST="${KPM}/dist"
HELPER="${KPM}/.tools/kpm-helper.py"
HELPER_URL="https://raw.githubusercontent.com/KindleModding/KPM/main/kpm-helper.py"
REPO="${1:-$(cd "${KPM}/.." && pwd)/kindlemodding-repo}"
MANIFEST="${REPO}/manifest.v2.json"

if [ ! -f "${HELPER}" ]; then
    echo "Downloading kpm-helper.py..."
    mkdir -p "$(dirname "${HELPER}")"
    curl -fsSL "${HELPER_URL}" -o "${HELPER}"
fi

if [ ! -d "${DIST}" ] || [ -z "$(ls "${DIST}"/*.kpkg 2>/dev/null)" ]; then
    echo "No .kpkg in ${DIST}; run ./pack.sh first." >&2
    exit 1
fi

if [ ! -f "${MANIFEST}" ]; then
    echo "Repository manifest not found: ${MANIFEST}" >&2
    echo "Clone the official repo, e.g.:" >&2
    echo "  git clone https://github.com/KindleModding/repo.git ${REPO}" >&2
    exit 1
fi

for kpkg in "${DIST}"/*.kpkg; do
    echo "Adding $(basename "${kpkg}")..."
    python3 "${HELPER}" repo add "${MANIFEST}" "${kpkg}"
done

echo
echo "Updated ${MANIFEST}"
python3 - <<PY
import json
with open("${MANIFEST}", encoding="utf-8") as fh:
    manifest = json.load(fh)
pkg = manifest.get("packages", {}).get("komarket")
if not pkg:
    print("komarket entry not found in manifest")
else:
    print(f"komarket artifacts: {len(pkg['artifacts'])}")
    for art in pkg["artifacts"]:
        platforms = ",".join(art.get("supported_platforms") or ["any"])
        version = ".".join(str(x) for x in art["version"])
        print(f"  - v{version} ({platforms}): {art['url']}")
PY

echo
echo "Next: commit and open a PR against KindleModding/repo"
