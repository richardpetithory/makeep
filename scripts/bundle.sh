#!/bin/zsh
# Builds MaKeep and wraps the binary in build.noindex/MaKeep.app (".noindex" keeps this
# working copy out of Spotlight; `make run` installs it to /Applications).
#
# Local builds sign with "MaKeep Local Signing" (see create-signing-cert.sh) when available,
# so Keychain access grants survive rebuilds, and fall back to ad-hoc signing otherwise.
#
# Overrides (used by release.sh):
#   MAKEEP_ARCHS          e.g. "arm64 x86_64" for a universal binary (default: host arch)
#   MAKEEP_APP_DIR        output directory for MaKeep.app (default: build.noindex)
#   MAKEEP_SIGN_IDENTITY  signing identity; also enables the hardened runtime and a secure
#                         timestamp, which notarization requires
set -euo pipefail
cd "${0:A:h}/.."

CONFIG="${1:-release}"
BUILD_FLAGS=(-c "$CONFIG")
for arch in ${=MAKEEP_ARCHS:-}; do BUILD_FLAGS+=(--arch "$arch"); done
swift build "${BUILD_FLAGS[@]}"
BIN="$(swift build "${BUILD_FLAGS[@]}" --show-bin-path)/makeep"

APP="${MAKEEP_APP_DIR:-build.noindex}/MaKeep.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/makeep"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# App icon, drawn by the app itself (MaKeepIcon) so it matches the menu bar icon.
ICONSET="$(mktemp -d)/AppIcon.iconset"
"$BIN" --render-iconset "$ICONSET"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "${ICONSET:h}"

LOCAL_IDENTITY="MaKeep Local Signing"
if [[ -n "${MAKEEP_SIGN_IDENTITY:-}" ]]; then
    codesign --force --options runtime --timestamp --sign "$MAKEEP_SIGN_IDENTITY" "$APP"
elif security find-certificate -c "$LOCAL_IDENTITY" >/dev/null 2>&1; then
    codesign --force --sign "$LOCAL_IDENTITY" "$APP"
else
    echo "warning: \"$LOCAL_IDENTITY\" not found; signing ad-hoc (run scripts/create-signing-cert.sh)" >&2
    codesign --force --sign - "$APP"
fi
echo "Built $APP"
