#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
app_dir="$project_dir/dist/Image Match Lab.app"
mkdir -p "$app_dir/Contents/MacOS"
cp "$project_dir/.build/release/PressIfImageFixture" "$app_dir/Contents/MacOS/PressIfImageFixture"
cat > "$app_dir/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.maakcode.press-if.image-fixture</string>
<key>CFBundleName</key><string>Image Match Lab</string>
<key>CFBundleExecutable</key><string>PressIfImageFixture</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
</dict></plist>
PLIST
codesign --force --sign - "$app_dir"
"$project_dir/.build/release/PressIfImageFixture" --export "$project_dir/verification/image-fixture"
