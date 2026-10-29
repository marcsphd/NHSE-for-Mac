#!/bin/bash
set -euo pipefail
if [[ "$#" -ne 2 ]]; then
    printf 'Usage: %s input.png output.icns\n' "$0" >&2
    exit 1
fi
TASK_PNG="$1"
TASK_ICON="$2"
TASK_TEMP="$(mktemp -d "${TMPDIR:-/tmp}/nhse-app-icon.XXXXXX")"
trap 'rm -rf "$TASK_TEMP"' EXIT
TASK_ICONSET="$TASK_TEMP/AppIcon.iconset"
mkdir -p "$TASK_ICONSET" "$(dirname "$TASK_ICON")"
for TASK_SIZE in 16 32 128 256 512; do
    sips -z "$TASK_SIZE" "$TASK_SIZE" "$TASK_PNG" --out "$TASK_ICONSET/icon_${TASK_SIZE}x${TASK_SIZE}.png" >/dev/null
    TASK_RETINA=$((TASK_SIZE * 2))
    sips -z "$TASK_RETINA" "$TASK_RETINA" "$TASK_PNG" --out "$TASK_ICONSET/icon_${TASK_SIZE}x${TASK_SIZE}@2x.png" >/dev/null
done
iconutil -c icns "$TASK_ICONSET" -o "$TASK_ICON"
printf 'Created: %s\n' "$TASK_ICON"
