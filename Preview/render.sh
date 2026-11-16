#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
bundle="$PWD/.build/preview/RitmPreview.app"
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources"
cat > "$bundle/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
    <key>CFBundleExecutable</key><string>RitmPreview</string>
    <key>CFBundleIdentifier</key><string>personal.ritm.preview</string>
</dict></plist>
PLIST
xcrun actool Config/Theme.xcassets --compile "$bundle/Contents/Resources" \
    --platform macosx --minimum-deployment-target 14.0 --target-device mac >/dev/null
out="${1:-$PWD/Preview/Ритм.png}"
swiftc -swift-version 5 -parse-as-library -DRITM_PREVIEW Config/RitmTheme.swift App/RitmApp.swift App/Core/*.swift App/UI/*.swift Preview/Render.swift -o "$bundle/Contents/MacOS/RitmPreview"
"$bundle/Contents/MacOS/RitmPreview" "$out" "${2:-$PWD/Preview/Каталог и пульс.png}"
