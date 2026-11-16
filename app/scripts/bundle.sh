#!/bin/bash
# 把 WinSteam 編好並組成 app/build/WinSteam.app（ad-hoc 簽章）。
# 用法：app/scripts/bundle.sh
set -euo pipefail

APP_DIR="$(cd "$(dirname "$0")/.." && pwd)"
REPO="$(cd "$APP_DIR/.." && pwd)"
OUT="$APP_DIR/build/WinSteam.app"
BUNDLE_ID="io.github.winsteam.app"

[ "$(uname -m)" = arm64 ] || { echo "✗ 只支援 Apple Silicon（arm64）" >&2; exit 1; }
[ -x "$REPO/bin/winsteam" ] || { echo "✗ 找不到 $REPO/bin/winsteam" >&2; exit 1; }
[ -d "$REPO/profiles" ] || { echo "✗ 找不到 $REPO/profiles" >&2; exit 1; }

echo "▸ 編譯（release, arm64）"
cd "$APP_DIR"
swift build -c release --arch arm64
BIN_DIR="$(swift build -c release --arch arm64 --show-bin-path)"

# 版本號跟著 CLI
VERSION="$(sed -n 's/^VERSION="\(.*\)"$/\1/p' "$REPO/bin/winsteam" | head -n 1)"
VERSION="${VERSION:-0.0.0}"
BUILD="$(git -C "$REPO" rev-list --count HEAD 2>/dev/null || echo 1)"

echo "▸ 組裝 $OUT"
rm -rf "$OUT"
mkdir -p "$OUT/Contents/MacOS" "$OUT/Contents/Resources/bin" "$OUT/Contents/Resources/zh-Hant.lproj"
cp "$BIN_DIR/WinSteam" "$OUT/Contents/MacOS/WinSteam"
# CLI 會用自己所在位置的 ../profiles，所以放在 Resources/bin 與 Resources/profiles
cp "$REPO/bin/winsteam" "$OUT/Contents/Resources/bin/winsteam"
chmod 755 "$OUT/Contents/Resources/bin/winsteam"
cp -R "$REPO/profiles" "$OUT/Contents/Resources/profiles"
# 有這個資料夾，系統提供的選單（結束、隱藏…）才會顯示繁體中文
printf '"CFBundleDisplayName" = "WinSteam";\n' > "$OUT/Contents/Resources/zh-Hant.lproj/InfoPlist.strings"

cat > "$OUT/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key><string>zh_TW</string>
  <key>CFBundleLocalizations</key><array><string>zh-Hant</string></array>
  <key>CFBundleExecutable</key><string>WinSteam</string>
  <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>WinSteam</string>
  <key>CFBundleDisplayName</key><string>WinSteam</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>${BUILD}</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
  <key>LSArchitecturePriority</key><array><string>arm64</string></array>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSRequiresNativeExecution</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSSupportsAutomaticTermination</key><false/>
</dict>
</plist>
EOF
plutil -lint "$OUT/Contents/Info.plist" >/dev/null

echo "▸ ad-hoc 簽章"
codesign -s - --force --deep "$OUT"
codesign --verify --deep --strict "$OUT"

echo "✓ 完成：$OUT"
