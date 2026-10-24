#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache"
APP="$PWD/dist/Stillpin.app"
mkdir -p dist
swift build --disable-sandbox -c release --arch arm64 --arch x86_64
BIN_DIR=$(swift build --disable-sandbox -c release --arch arm64 --arch x86_64 --show-bin-path)
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Stillpin" "$APP/Contents/MacOS/Stillpin"
mkdir -p .build/Stillpin.iconset
xcrun swift scripts/icon.swift "$PWD/.build/Stillpin.iconset"
iconutil -c icns .build/Stillpin.iconset -o "$APP/Contents/Resources/Stillpin.icns"
cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - --identifier app.xdlkc.stillpin "$APP"
codesign --verify --strict "$APP"
lipo "$APP/Contents/MacOS/Stillpin" -verify_arch arm64 x86_64
ditto -c -k --sequesterRsrc --keepParent "$APP" dist/Stillpin-universal.zip
shasum -a 256 dist/Stillpin-universal.zip > dist/SHA256SUMS.txt
printf 'Built %s (ad-hoc signed, not notarized)\n' "$APP"
