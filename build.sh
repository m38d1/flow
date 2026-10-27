#!/bin/zsh
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="Flow"
BUILD_DIR="build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
SOURCES=(Sources/Core.swift Sources/NetworkSampler.swift Sources/FlowModel.swift Sources/Views.swift Sources/main.swift)
FRAMEWORKS=(-framework Cocoa -framework SwiftUI -framework Charts -framework SystemConfiguration -framework ServiceManagement)

if [[ -w /Applications ]]; then
    INSTALL_DIR="/Applications"
else
    INSTALL_DIR="$HOME/Applications"
fi

pkill -f "$INSTALL_DIR/$APP_NAME.app/Contents/MacOS/$APP_NAME" 2>/dev/null || true
pkill -f "$PWD/$APP_BUNDLE/Contents/MacOS/$APP_NAME" 2>/dev/null || true

rm -rf "$BUILD_DIR"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"

swiftc -O -swift-version 5 -target arm64-apple-macosx13.0 "${SOURCES[@]}" \
    -o "$BUILD_DIR/$APP_NAME-arm64" "${FRAMEWORKS[@]}"

swiftc -O -swift-version 5 -target x86_64-apple-macosx13.0 "${SOURCES[@]}" \
    -o "$BUILD_DIR/$APP_NAME-x86_64" "${FRAMEWORKS[@]}"

lipo -create "$BUILD_DIR/$APP_NAME-arm64" "$BUILD_DIR/$APP_NAME-x86_64" \
    -output "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

swiftc -O -swift-version 5 make-icon.swift -o "$BUILD_DIR/make-icon" -framework AppKit
"$BUILD_DIR/make-icon" "$BUILD_DIR/icon-render.png" >/dev/null
rm -rf "$BUILD_DIR/Icon.iconset"
mkdir -p "$BUILD_DIR/Icon.iconset"
for size in 16 32 128 256 512; do
    sips -z $size $size "$BUILD_DIR/icon-render.png" --out "$BUILD_DIR/Icon.iconset/icon_${size}x${size}.png" >/dev/null
    sips -z $((size * 2)) $((size * 2)) "$BUILD_DIR/icon-render.png" --out "$BUILD_DIR/Icon.iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$BUILD_DIR/Icon.iconset" -o "$BUILD_DIR/$APP_NAME.icns"

cp Info.plist "$APP_BUNDLE/Contents/Info.plist"
cp "$BUILD_DIR/$APP_NAME.icns" "$APP_BUNDLE/Contents/Resources/$APP_NAME.icns"
codesign --force --sign - "$APP_BUNDLE"

/usr/bin/ditto "$APP_BUNDLE" "$INSTALL_DIR/$APP_NAME.app"

/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
    -f "$INSTALL_DIR/$APP_NAME.app" >/dev/null 2>&1 || true

echo "Installed: $INSTALL_DIR/$APP_NAME.app"
