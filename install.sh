#!/usr/bin/env bash
#
# install.sh — build NoDoze in Release configuration and install it into /Applications.
#
# NoDoze is a plain Xcode project with no external dependencies, so this just
# drives xcodebuild and copies the resulting .app into place. It ad-hoc signs
# the build (no Apple Developer certificate required) so macOS will launch it.
#
# Usage:
#   ./install.sh            # build + install to /Applications, then launch
#   ./install.sh --no-open  # build + install, but don't launch
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

PROJECT="NoDoze.xcodeproj"
SCHEME="NoDoze"
APP_NAME="NoDoze.app"
DEST="/Applications/$APP_NAME"
BUILD_DIR="$SCRIPT_DIR/build"

OPEN_AFTER=1
for arg in "$@"; do
  case "$arg" in
    --no-open) OPEN_AFTER=0 ;;
    -h|--help) sed -n '2,14p' "$0"; exit 0 ;;
    *) echo "Unknown argument: $arg" >&2; exit 2 ;;
  esac
done

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "error: xcodebuild not found. Install Xcode (not just the Command Line Tools)." >&2
  exit 1
fi

echo "==> Building $SCHEME (Release)…"
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -derivedDataPath "$BUILD_DIR" \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  build

BUILT_APP="$BUILD_DIR/Build/Products/Release/$APP_NAME"
if [[ ! -d "$BUILT_APP" ]]; then
  echo "error: build did not produce $BUILT_APP" >&2
  exit 1
fi

echo "==> Ad-hoc signing…"
codesign --force --deep --sign - "$BUILT_APP"

echo "==> Quitting any running instance…"
osascript -e 'quit app "NoDoze"' >/dev/null 2>&1 || true
pkill -x NoDoze >/dev/null 2>&1 || true

echo "==> Installing to $DEST…"
rm -rf "$DEST"
cp -R "$BUILT_APP" "$DEST"
xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true

echo "==> Installed $DEST"

if [[ "$OPEN_AFTER" -eq 1 ]]; then
  echo "==> Launching…"
  open "$DEST"
  echo "NoDoze is running — look for its icon in the menu bar."
else
  echo "Done. Launch it from /Applications or Spotlight when ready."
fi
