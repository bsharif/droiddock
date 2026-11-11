#!/bin/bash
# Builds dist/DroidDock.app (SwiftUI front end + Rust adb engine).
#
#   ./packaging/build-app.sh              build for this Mac's CPU
#   ./packaging/build-app.sh --install    build and copy to /Applications
#   ./packaging/build-app.sh --zip        build and make dist/DroidDock-vX.Y.Z-macos.zip
#   UNIVERSAL=1 ./packaging/build-app.sh  build for Apple Silicon and Intel
#                                         (needs: rustup target add aarch64-apple-darwin x86_64-apple-darwin)
set -euo pipefail
cd "$(dirname "$0")/.."

APP="dist/DroidDock.app"
VERSION=$(grep -m1 '^version' Cargo.toml | cut -d'"' -f2)
MIN_MACOS=14.0
mkdir -p build dist

if [ "${UNIVERSAL:-0}" = "1" ]; then
  ARCHS="arm64 x86_64"
else
  ARCHS="$(uname -m)"
fi

rust_target() { [ "$1" = "arm64" ] && echo aarch64-apple-darwin || echo x86_64-apple-darwin; }

echo "==> DroidDock $VERSION for: $ARCHS"
ENGINES=() ; APPS=()
for arch in $ARCHS; do
  echo "==> Rust engine ($arch)"
  if [ "${UNIVERSAL:-0}" = "1" ]; then
    t=$(rust_target "$arch")
    MACOSX_DEPLOYMENT_TARGET=$MIN_MACOS cargo build --release --target "$t"
    ENGINES+=("target/$t/release/droiddock-engine")
  else
    MACOSX_DEPLOYMENT_TARGET=$MIN_MACOS cargo build --release
    ENGINES+=("target/release/droiddock-engine")
  fi
  echo "==> SwiftUI app ($arch)"
  swiftc -parse-as-library -O -swift-version 5 -target "$arch-apple-macos$MIN_MACOS" \
    -o "build/DroidDock-$arch" macos/*.swift
  APPS+=("build/DroidDock-$arch")
done

echo "==> Icon"
ICONSET=build/AppIcon.iconset
rm -rf "$ICONSET" && mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
  sips -z $s $s packaging/icon-1024.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) packaging/icon-1024.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o build/AppIcon.icns

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
lipo -create "${APPS[@]}" -output "$APP/Contents/MacOS/DroidDock"
lipo -create "${ENGINES[@]}" -output "$APP/Contents/MacOS/droiddock-engine"
cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>DroidDock</string>
  <key>CFBundleDisplayName</key><string>DroidDock</string>
  <key>CFBundleIdentifier</key><string>io.github.bsharif.droiddock</string>
  <key>CFBundleExecutable</key><string>DroidDock</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>${VERSION}</string>
  <key>LSMinimumSystemVersion</key><string>${MIN_MACOS}</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSHumanReadableCopyright</key><string>MIT License. Not affiliated with Google or Android.</string>
  <key>NSLocalNetworkUsageDescription</key>
  <string>DroidDock finds and connects to your Android phone over Wi-Fi (wireless adb).</string>
  <key>NSBonjourServices</key>
  <array>
    <string>_adb._tcp</string>
    <string>_adb-tls-connect._tcp</string>
    <string>_adb-tls-pairing._tcp</string>
  </array>
</dict>
</plist>
PLIST

echo "==> Signing (ad hoc)"
codesign --force --deep --sign - "$APP"
echo "==> Architectures: $(lipo -archs "$APP/Contents/MacOS/DroidDock")"

for arg in "$@"; do
  case "$arg" in
    --install)
      echo "==> Installing to /Applications"
      rm -rf "/Applications/DroidDock.app"
      cp -R "$APP" /Applications/
      echo "Installed: /Applications/DroidDock.app" ;;
    --zip)
      ZIP="dist/DroidDock-v${VERSION}-macos.zip"
      rm -f "$ZIP"
      ditto -c -k --keepParent "$APP" "$ZIP"
      (cd dist && shasum -a 256 "$(basename "$ZIP")" | tee "$(basename "$ZIP").sha256")
      echo "Zipped: $ZIP" ;;
  esac
done
echo "Built: $APP"
