#!/bin/sh
# Build .kpkg files and sync them into a self-hosted KPM repo via kpm-helper repo add.
#
# Usage:
#   ./repo-sync.sh [REPO_PATH]
#
# Default REPO_PATH: ../kpm-repo
set -e

KPM="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "${KPM}/.." && pwd)"
REPO="${1:-${ROOT}/kpm-repo}"
DIST="${KPM}/dist"
HELPER="${KPM}/.tools/kpm-helper.py"
HELPER_URL="https://raw.githubusercontent.com/KindleModding/KPM/main/kpm-helper.py"
MANIFEST="${REPO}/manifest.v2.json"
VERSION_FILE="${ROOT}/komarket.koplugin/_version.lua"
PKG_MANIFEST="${KPM}/package/manifest.json"
PLATFORMS="kindlehf kindlepw2"

if [ ! -f "${HELPER}" ]; then
    echo "Downloading kpm-helper.py..."
    mkdir -p "$(dirname "${HELPER}")"
    curl -fsSL "${HELPER_URL}" -o "${HELPER}"
fi

if [ ! -f "${MANIFEST}" ]; then
    echo "Initialising repository at ${REPO}..."
    "${KPM}/repo-init.sh" "${REPO}"
fi

VERSION="$(sed -n 's/^return "\(.*\)"/\1/p' "${VERSION_FILE}")"
if [ -z "${VERSION}" ]; then
    echo "Could not read version from ${VERSION_FILE}" >&2
    exit 1
fi

python3 - "${PKG_MANIFEST}" "${VERSION}" <<'PY'
import json
import sys

manifest_path, version = sys.argv[1], sys.argv[2]
major, minor, patch = version.split(".")
with open(manifest_path, encoding="utf-8") as fh:
    manifest = json.load(fh)
manifest["version"] = [int(major), int(minor), int(patch)]
with open(manifest_path, "w", encoding="utf-8") as fh:
    json.dump(manifest, fh, indent=2)
    fh.write("\n")
PY

echo "Building komarket v${VERSION}..."
"${KPM}/pack.sh"

for platform in ${PLATFORMS}; do
    echo "Removing existing v${VERSION} (${platform}) if present..."
    python3 "${HELPER}" repo remove "${MANIFEST}" komarket \
        --version "${VERSION}" \
        --supported_platform "${platform}" 2>/dev/null || true
done

for kpkg in "${DIST}/"*.kpkg; do
    echo "Adding $(basename "${kpkg}")..."
    python3 "${HELPER}" repo add "${MANIFEST}" "${kpkg}"
done

echo
echo "Synced ${REPO}"
python3 - <<PY
import json

with open("${MANIFEST}", encoding="utf-8") as fh:
    manifest = json.load(fh)
pkg = manifest["packages"]["komarket"]
print(f"Repository: {manifest['id']} — {manifest['name']}")
print(f"komarket artifacts: {len(pkg['artifacts'])}")
for art in pkg["artifacts"]:
    platforms = ",".join(art.get("supported_platforms") or ["any"])
    version = ".".join(str(x) for x in art["version"])
    print(f"  - v{version} ({platforms}): {art['url']}")
PY

echo
echo "Host this folder statically, then on Kindle:"
echo "  ;kpm add-repo https://raw.githubusercontent.com/Exhen/komarket-public/main/kpm-repo/manifest.v2.json"
echo "  ;kpm update"
echo "  ;kpm install komarket"
