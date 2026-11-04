#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_dir"
if pgrep -x PressIfMeta >/dev/null; then
    printf '%s\n' 'Quit Press If before replacing its app bundle.' >&2
    exit 1
fi
if [[ -d /Applications/Xcode.app/Contents/Developer ]]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
export CLANG_MODULE_CACHE_PATH="$project_dir/.build/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$project_dir/.build/module-cache"
swift build --disable-sandbox --build-system native -c release --scratch-path "$project_dir/.build" --cache-path "$project_dir/.build/cache" --config-path "$project_dir/.build/config" --security-path "$project_dir/.build/security"
app_dir="$project_dir/dist/Press If.app"
previous_app_dir="$project_dir/dist/Press If Meta.app"
if [[ -d "$previous_app_dir" && ! -e "$app_dir" ]]; then
    mv "$previous_app_dir" "$app_dir"
fi
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$project_dir/.build/release/PressIfMeta" "$app_dir/Contents/MacOS/PressIfMeta"
cp "$project_dir/Resources/Info.plist" "$app_dir/Contents/Info.plist"
swift -module-cache-path "$project_dir/.build/module-cache" "$project_dir/scripts/make-icon.swift" "$project_dir/.build/AppIcon.iconset"
iconutil -c icns "$project_dir/.build/AppIcon.iconset" -o "$app_dir/Contents/Resources/AppIcon.icns"
bash "$project_dir/scripts/sign-app.sh" "$app_dir"
printf '%s\n' "$app_dir"
