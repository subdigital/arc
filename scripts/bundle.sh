#!/bin/sh
# Builds a release and assembles build/Arc.app (signed ad hoc, for local use).
#
#   Contents/MacOS/ArcApp      the SwiftUI app
#   Contents/Helpers/arc       the command-line tool / MCP server
#   Contents/Resources/        icon + SwiftPM resource bundles
#
# The app executable is not called "Arc": APFS is case-insensitive, so it would collide with "arc".
set -eu
cd "$(dirname "$0")/.."

swift build -c release
BIN="$(swift build -c release --show-bin-path)"

APP="build/Arc.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Helpers" "$APP/Contents/Resources"

cp "$BIN/ArcApp" "$APP/Contents/MacOS/ArcApp"
cp "$BIN/arc" "$APP/Contents/Helpers/arc"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
for bundle in "$BIN"/*.bundle; do
    [ -e "$bundle" ] && cp -R "$bundle" "$APP/Contents/Resources/"
done

# Helper first, then the app that contains it.
codesign --force --sign - "$APP/Contents/Helpers/arc"
codesign --force --sign - "$APP"
codesign --verify --strict "$APP"

echo "Built $APP"
