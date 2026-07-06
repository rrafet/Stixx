#!/bin/bash
# Builds Stixx.app: compiles the SPM executable, wraps it in a proper
# app bundle, and ad-hoc signs it with App Sandbox enabled.
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Stixx"
APP_DIR="$APP_NAME.app"

# Build each architecture separately and merge with lipo: passing both
# --arch flags to a single swift build requires full Xcode, while this
# form works with Command Line Tools alone.
echo "Building $APP_NAME (release, arm64)..."
swift build -c release --arch arm64
echo "Building $APP_NAME (release, x86_64)..."
swift build -c release --arch x86_64

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

lipo -create \
    ".build/arm64-apple-macosx/release/$APP_NAME" \
    ".build/x86_64-apple-macosx/release/$APP_NAME" \
    -output "$APP_DIR/Contents/MacOS/$APP_NAME"
cp "Packaging/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "Packaging/PrivacyInfo.xcprivacy" "$APP_DIR/Contents/Resources/PrivacyInfo.xcprivacy"
printf 'APPL????' > "$APP_DIR/Contents/PkgInfo"

ICON_SRC="Packaging/AppIcon.png"
if [ -f "$ICON_SRC" ]; then
    echo "Generating app icon from $ICON_SRC..."
    ICONSET_DIR=".AppIcon.iconset"
    rm -rf "$ICONSET_DIR"
    mkdir -p "$ICONSET_DIR"
    sips -z 16 16     "$ICON_SRC" --out "$ICONSET_DIR/icon_16x16.png"      >/dev/null
    sips -z 32 32     "$ICON_SRC" --out "$ICONSET_DIR/icon_16x16@2x.png"   >/dev/null
    sips -z 32 32     "$ICON_SRC" --out "$ICONSET_DIR/icon_32x32.png"      >/dev/null
    sips -z 64 64     "$ICON_SRC" --out "$ICONSET_DIR/icon_32x32@2x.png"   >/dev/null
    sips -z 128 128   "$ICON_SRC" --out "$ICONSET_DIR/icon_128x128.png"    >/dev/null
    sips -z 256 256   "$ICON_SRC" --out "$ICONSET_DIR/icon_128x128@2x.png" >/dev/null
    sips -z 256 256   "$ICON_SRC" --out "$ICONSET_DIR/icon_256x256.png"    >/dev/null
    sips -z 512 512   "$ICON_SRC" --out "$ICONSET_DIR/icon_256x256@2x.png" >/dev/null
    sips -z 512 512   "$ICON_SRC" --out "$ICONSET_DIR/icon_512x512.png"    >/dev/null
    sips -z 1024 1024 "$ICON_SRC" --out "$ICONSET_DIR/icon_512x512@2x.png" >/dev/null
    iconutil -c icns "$ICONSET_DIR" -o "$APP_DIR/Contents/Resources/AppIcon.icns"
    rm -rf "$ICONSET_DIR"
else
    echo "No $ICON_SRC found — using the default icon."
    echo "Drop a 1024x1024 PNG at $ICON_SRC and rerun build.sh to set a custom icon."
fi

# Packaging/AppIcon-dark.png is intentionally not bundled: a dark icon
# should only appear when macOS itself decides to show dark icons, which
# requires an asset catalog compiled with Xcode's actool. Until then the
# icon stays light everywhere, consistent with other apps.

# --options runtime enables the Hardened Runtime, which blocks debugger
# attachment and DYLD_INSERT_LIBRARIES code injection into the running app.
echo "Signing (ad-hoc, App Sandbox + Hardened Runtime enabled)..."
codesign --force --options runtime --sign - --entitlements "Packaging/Stixx.entitlements" "$APP_DIR"

echo "Done: $APP_DIR"
echo "Launch with: open $APP_DIR"
