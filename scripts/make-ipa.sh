#!/usr/bin/env bash
# Builds an UNSIGNED .ipa for sideloading. Sideloading tools re-sign the bundle
# themselves, so signing here would only be thrown away.
#
#   Release       entitlements request the App Group (TrollStore and other tools
#                 that can grant arbitrary entitlements)
#   Free-Release  no entitlements (AltStore / SideStore, which sign with a free
#                 personal team and cannot grant App Groups)
#
# The .ipa is verified after packaging: a build that silently drops an
# extension is worse than one that fails outright, since the user would
# sideload it, see no Dynamic Island, and have no idea why.
set -euo pipefail

CONFIG="${1:-Release}"
case "$CONFIG" in
  Release)      SCHEME="IslandTray" ;;
  Free-Release) SCHEME="IslandTray (Free)" ;;
  *) echo "usage: $0 [Release|Free-Release]" >&2; exit 2 ;;
esac

cd "$(dirname "$0")/.."
command -v xcodegen >/dev/null && xcodegen generate

BUILD_DIR="build/$CONFIG"
rm -rf "$BUILD_DIR"

# Clear any previous .ipa for this config up front, before the build even
# starts, not right before the final zip. A run that fails partway through
# (build error, a verification check below) must not leave an older .ipa
# sitting in build/ where a rerun-after-a-failure could be mistaken for
# fresh output -- better an absent artifact than a stale one that looks current.
OUT="$PWD/build/IslandTray-$CONFIG.ipa"
rm -f "$OUT"

xcodebuild build \
  -project IslandTray.xcodeproj \
  -scheme "$SCHEME" \
  -configuration "$CONFIG" \
  -sdk iphoneos \
  -derivedDataPath "$BUILD_DIR" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  | tail -5

APP="$BUILD_DIR/Build/Products/$CONFIG-iphoneos/IslandTray.app"
[ -d "$APP" ] || { echo "app bundle not found at $APP" >&2; exit 1; }

# --- Verify the built .app before packaging, not after -----------------
# A build product missing its extensions is a silent failure: catch it here
# so the .ipa is never written with a broken bundle.
for EXT in IslandTrayWidget IslandTrayShare; do
  APPEX="$APP/PlugIns/$EXT.appex"
  [ -d "$APPEX" ] || { echo "missing extension: $APPEX" >&2; exit 1; }
done

PLIST="$APP/Info.plist"
if ! plutil -p "$PLIST" | grep -qE "\"NSSupportsLiveActivities\" => (1|true)"; then
  echo "Info.plist is missing NSSupportsLiveActivities" >&2
  exit 1
fi
# Scoped to the CFBundleURLSchemes array itself, not a bare grep over the
# whole plist dump: CFBundleIdentifier (com.pikare.islandtray) and
# CFBundleURLName (also com.pikare.islandtray) both contain the substring
# "islandtray", so an unscoped grep passes even with CFBundleURLTypes deleted
# entirely -- which defeats the point of checking for the URL scheme at all.
url_schemes() { plutil -extract CFBundleURLTypes.0.CFBundleURLSchemes json -o - "$1" 2>/dev/null; }
url_schemes "$PLIST" | grep -q '"islandtray"' || {
  echo "Info.plist is missing the islandtray URL scheme (CFBundleURLSchemes)" >&2
  exit 1
}

# Entitlements actually baked into each target must match what this
# configuration intends: App Group present for Release, absent for Free-Release.
# CODE_SIGNING_ALLOWED=NO means xcodebuild never signs the binaries, so there
# is nothing for `codesign -d --entitlements` to read back off them -- check
# the CODE_SIGN_ENTITLEMENTS files project.yml points each config at instead.
# NOTE: this trusts the CONFIG->ENT_DIR mapping below to match project.yml's
# own CODE_SIGN_ENTITLEMENTS setting for each target/config -- it does not
# read project.yml itself, so a copy-paste slip there (e.g. Release pointed
# at Entitlements/Free/App.entitlements) would build with the wrong
# entitlements and this check would still report "verified". Real limit of
# verifying an unsigned build; see task-12-review.md Important #2.
check_entitlements_file() {
  local FILE="$1" LABEL="$2"
  local HAS_GROUP=0
  grep -q "com.apple.security.application-groups" "$FILE" && HAS_GROUP=1
  if [ "$CONFIG" = "Release" ] && [ "$HAS_GROUP" -ne 1 ]; then
    echo "$LABEL: expected App Group entitlement for Release, found none" >&2
    exit 1
  fi
  if [ "$CONFIG" = "Free-Release" ] && [ "$HAS_GROUP" -eq 1 ]; then
    echo "$LABEL: Free-Release must not request the App Group" >&2
    exit 1
  fi
}
ENT_DIR="Entitlements/Paid"
[ "$CONFIG" = "Free-Release" ] && ENT_DIR="Entitlements/Free"
check_entitlements_file "$ENT_DIR/App.entitlements" "App"
check_entitlements_file "$ENT_DIR/Widget.entitlements" "Widget"
check_entitlements_file "$ENT_DIR/Share.entitlements" "Share"

STAGE="$BUILD_DIR/stage"
rm -rf "$STAGE"; mkdir -p "$STAGE/Payload"
cp -R "$APP" "$STAGE/Payload/"

(cd "$STAGE" && zip -qry "$OUT" Payload)

# --- Verify the packaged .ipa itself, not just the pre-zip .app --------
# Re-check straight off the zip so packaging bugs (wrong staging path,
# partial copy) can't slip through even if the .app above was fine.
IPA_LIST="$(unzip -l "$OUT")"
for EXT in IslandTrayWidget IslandTrayShare; do
  echo "$IPA_LIST" | grep -q "Payload/IslandTray.app/PlugIns/$EXT.appex/" \
    || { echo "$OUT is missing Payload/IslandTray.app/PlugIns/$EXT.appex/" >&2; exit 1; }
done
IPA_PLIST="$(unzip -p "$OUT" Payload/IslandTray.app/Info.plist | plutil -p -)"
echo "$IPA_PLIST" | grep -qE "\"NSSupportsLiveActivities\" => (1|true)" \
  || { echo "$OUT's Info.plist is missing NSSupportsLiveActivities" >&2; exit 1; }
unzip -p "$OUT" Payload/IslandTray.app/Info.plist | url_schemes - | grep -q '"islandtray"' \
  || { echo "$OUT's Info.plist is missing the islandtray URL scheme (CFBundleURLSchemes)" >&2; exit 1; }
# The settings screen installs these; a build without them (v1.1.4 shipped
# that way) leaves both install buttons dead.
for SC in ClipboardToTray ShareToTray; do
  echo "$IPA_LIST" | grep -q "Payload/IslandTray.app/$SC.shortcut" \
    || { echo "$OUT is missing Payload/IslandTray.app/$SC.shortcut" >&2; exit 1; }
done

echo "verified: PlugIns/{IslandTrayWidget,IslandTrayShare}.appex, shortcuts, Info.plist keys, $CONFIG entitlements"
echo "wrote $OUT ($(du -h "$OUT" | cut -f1))"
