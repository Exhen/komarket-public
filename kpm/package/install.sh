#!/bin/sh
# Install komarket.koplugin into KOReader's plugins directory.
# Runs from the unpacked KPM package folder (relative paths are safe).

PLUGIN_DIRNAME="komarket.koplugin"
KOREADER_ROOT="/mnt/us/koreader"
PLUGINS_DIR="${KOREADER_ROOT}/plugins"
SRC="./payload/${PLUGIN_DIRNAME}"
DEST="${PLUGINS_DIR}/${PLUGIN_DIRNAME}"

if [ ! -d "${KOREADER_ROOT}" ]; then
    echo "KOReader not found at ${KOREADER_ROOT}"
    echo "Install KOReader first: ;kpm install koreader"
    exit 1
fi

if [ ! -d "${SRC}" ]; then
    echo "Plugin payload missing: ${SRC}"
    exit 1
fi

if [ ! -f "${SRC}/_meta.lua" ] || [ ! -f "${SRC}/main.lua" ]; then
    echo "Invalid plugin payload (missing _meta.lua or main.lua)"
    exit 1
fi

mkdir -p "${PLUGINS_DIR}"

if [ -d "${DEST}" ]; then
    echo "Removing previous ${PLUGIN_DIRNAME}..."
    rm -rf "${DEST}"
fi

echo "Installing ${PLUGIN_DIRNAME} to ${PLUGINS_DIR}..."
cp -r "${SRC}" "${DEST}"

if [ ! -f "${DEST}/_meta.lua" ] || [ ! -f "${DEST}/main.lua" ]; then
    echo "Installation verification failed"
    exit 1
fi

if [ "$1" = "upgrade" ]; then
    echo "KOMarket plugin upgraded. Restart KOReader to load the new version."
else
    echo "KOMarket plugin installed."
    echo "Restart KOReader, then open Tools → Plugin management to enable it."
fi

exit 0
