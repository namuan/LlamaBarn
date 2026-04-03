#!/bin/bash
set -euo pipefail

# Require only Xcode Command Line Tools — full Xcode is NOT needed.
# Install them with: xcode-select --install
if ! command -v swift >/dev/null 2>&1; then
  echo "Error: 'swift' not found."
  echo "Install Xcode Command Line Tools (no full Xcode needed):"
  echo "  xcode-select --install"
  exit 1
fi

# Ensure the active developer directory is set (CLT or Xcode either works).
if ! xcode-select -p >/dev/null 2>&1; then
  echo "Error: No active developer directory found."
  echo "Run: xcode-select --install"
  exit 1
fi

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="LlamaBarn"
PROJECT="$ROOT/LlamaBarn.xcodeproj"
DEST_DIR="$HOME/Applications"
DEST_APP="$DEST_DIR/$APP_NAME.app"

echo "Resolving package dependencies..."
xcodebuild -resolvePackageDependencies -project "$PROJECT" -quiet

echo "Building $APP_NAME (Release)..."
xcodebuild -project "$PROJECT" \
  -scheme "$APP_NAME" \
  -configuration Release \
  -destination "platform=macOS,arch=arm64" \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  -derivedDataPath "$ROOT/.build" \
  build -quiet

# Find the built app in DerivedData
BUILT_APP=$(find "$ROOT/.build/Build/Products/Release" -name "$APP_NAME.app" -type d | head -1)

if [ -z "$BUILT_APP" ] || [ ! -d "$BUILT_APP" ]; then
  echo "Error: Build succeeded but app bundle not found."
  echo "Searched in: $ROOT/.build/Build/Products/Release"
  exit 1
fi

echo "Installing to ${DEST_APP}..."
mkdir -p "$DEST_DIR"
rm -rf "$DEST_APP"
cp -R "$BUILT_APP" "$DEST_APP"

echo "Done."
open "$DEST_APP"
