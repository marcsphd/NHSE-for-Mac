#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
TASK_ROOT="$PWD"
TASK_OUTPUT="${ACNH_BUILD_OUTPUT:-$TASK_ROOT/dist}"
TASK_APP="$TASK_OUTPUT/ACNH Save Editor.app"
TASK_ARCH="${1:-universal}"
TASK_SCRATCH="${ACNH_BUILD_SCRATCH:-$TASK_ROOT/.build}"
export CLANG_MODULE_CACHE_PATH="$TASK_SCRATCH/ModuleCache"
export SWIFT_MODULECACHE_PATH="$TASK_SCRATCH/SwiftModuleCache"
swift_package() { swift build "$@" --scratch-path "$TASK_SCRATCH" -debug-info-format none --disable-sandbox --cache-path "$TASK_ROOT/.build/cache" --config-path "$TASK_ROOT/.build/config" --security-path "$TASK_ROOT/.build/security"; }
if [[ "$TASK_ARCH" == "universal" ]]; then
    swift_package -c release --arch arm64 --arch x86_64
    TASK_BIN="$(swift_package -c release --arch arm64 --arch x86_64 --show-bin-path)"
else
    swift_package -c release
    TASK_BIN="$(swift_package -c release --show-bin-path)"
fi
mkdir -p "$TASK_APP/Contents/MacOS" "$TASK_APP/Contents/Resources"
cp "$TASK_BIN/ACNHSaveEditor" "$TASK_APP/Contents/MacOS/ACNHSaveEditor"
for TASK_BUNDLE in "$TASK_BIN"/*.bundle; do
    [[ -d "$TASK_BUNDLE" ]] && cp -R "$TASK_BUNDLE" "$TASK_APP/Contents/Resources/"
done
cp Info.plist "$TASK_APP/Contents/Info.plist"
cp AppIcon.icns "$TASK_APP/Contents/Resources/AppIcon.icns"
codesign --force --deep --sign - "$TASK_APP"
codesign --verify --deep --strict "$TASK_APP"
cp README.md "$TASK_OUTPUT/Read Me.md"
cp LICENSE "$TASK_OUTPUT/LICENSE-GPL-3.0.txt"
cp THIRD-PARTY-NOTICES.md "$TASK_OUTPUT/Third Party Notices.md"
printf 'Built: %s\n' "$TASK_APP"
