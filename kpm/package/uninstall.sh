#!/bin/sh
# Remove komarket.koplugin from KOReader's plugins directory.

PLUGIN_DIRNAME="komarket.koplugin"
DEST="/mnt/us/koreader/plugins/${PLUGIN_DIRNAME}"

if [ "$1" = "upgrade" ]; then
    echo "Upgrade in progress — keeping existing plugin until install.sh runs."
    exit 0
fi

if [ -d "${DEST}" ]; then
    echo "Removing ${PLUGIN_DIRNAME} from KOReader plugins..."
    rm -rf "${DEST}"
else
    echo "Plugin not installed at ${DEST} (nothing to remove)."
fi

exit 0
