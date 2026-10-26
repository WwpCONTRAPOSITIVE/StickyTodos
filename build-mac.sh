#!/bin/bash
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "请在 Mac 上运行这个脚本。" >&2
  exit 1
fi

project_dir="$(cd "$(dirname "$0")" && pwd)"
app_dir="$project_dir/dist/StickyTodos.app"
contents_dir="$app_dir/Contents"

mkdir -p "$contents_dir/MacOS"

cat > "$contents_dir/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key><string>zh_CN</string>
  <key>CFBundleExecutable</key><string>StickyTodos</string>
  <key>CFBundleIdentifier</key><string>local.stickytodos.app</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>Todo 便签</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.4</string>
  <key>CFBundleVersion</key><string>5</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

xcrun swiftc \
  -parse-as-library \
  -O \
  -target "$(uname -m)-apple-macosx13.0" \
  -framework AppKit \
  -framework SwiftUI \
  -o "$contents_dir/MacOS/StickyTodos" \
  "$project_dir/Sources/"*.swift

echo "已生成 $app_dir"
echo "运行：open '$app_dir'"
