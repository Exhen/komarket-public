#!/bin/sh
# Build komarket.kpkg for each supported Kindle platform.
set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
KPM="$(cd "$(dirname "$0")" && pwd)"
PKG="${KPM}/package"
PAYLOAD="${PKG}/payload/komarket.koplugin"
DIST="${KPM}/dist"
HELPER="${KPM}/.tools/kpm-helper.py"
HELPER_URL="https://raw.githubusercontent.com/KindleModding/KPM/main/kpm-helper.py"
MANIFEST="${PKG}/manifest.json"

# KPM platform identifiers — see:
# https://kindlemodding.org/kindle-dev/kpm/creating-a-package.html
PLATFORMS="kindle kindle5 kindlepw2 kindlehf"

PLUGIN_SRC="${ROOT}/komarket.koplugin"
if [ ! -d "${PLUGIN_SRC}" ]; then
    echo "Plugin source not found: ${PLUGIN_SRC}" >&2
    exit 1
fi

if [ ! -f "${HELPER}" ]; then
    echo "Downloading kpm-helper.py..."
    mkdir -p "$(dirname "${HELPER}")"
    curl -fsSL "${HELPER_URL}" -o "${HELPER}"
fi

echo "Syncing plugin into package/payload/..."
rm -rf "${PKG}/payload"
mkdir -p "${PKG}/payload"
cp -R "${PLUGIN_SRC}" "${PAYLOAD}"

chmod +x "${PKG}/install.sh" "${PKG}/uninstall.sh"
mkdir -p "${DIST}"
rm -f "${DIST}/"*.kpkg

set_platform_manifest() {
    python3 - "${MANIFEST}" "$1" <<'PY'
import json
import sys

manifest_path, platform = sys.argv[1], sys.argv[2]
with open(manifest_path, encoding="utf-8") as fh:
    manifest = json.load(fh)
manifest["supported_platforms"] = [platform]
with open(manifest_path, "w", encoding="utf-8") as fh:
    json.dump(manifest, fh, indent=2)
    fh.write("\n")
PY
}

restore_manifest() {
    python3 - "${MANIFEST}" <<'PY'
import json
import sys

manifest_path = sys.argv[1]
platforms = ["kindle", "kindle5", "kindlepw2", "kindlehf"]
with open(manifest_path, encoding="utf-8") as fh:
    manifest = json.load(fh)
manifest["supported_platforms"] = platforms
with open(manifest_path, "w", encoding="utf-8") as fh:
    json.dump(manifest, fh, indent=2)
    fh.write("\n")
PY
}

for platform in ${PLATFORMS}; do
    echo "Packing for ${platform}..."
    set_platform_manifest "${platform}"
    python3 "${HELPER}" package pack "${PKG}" "${DIST}"
done

restore_manifest

echo
echo "Built ${DIST}/:"
ls -lh "${DIST}/"*.kpkg
