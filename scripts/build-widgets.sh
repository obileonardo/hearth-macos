#!/bin/zsh
# Compile the optional macOS WidgetKit extension without installing/registering it.
# This unsigned build verifies source/architecture, not gallery availability.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/sdk.sh
output="${HEARTH_WIDGET_OUTPUT:-build/HearthWidgets.appex}"
universal=false
for arg in "$@"; do
  case "$arg" in
    --universal) universal=true ;;
    *) print -u2 "Usage: scripts/build-widgets.sh [--universal]"; exit 1 ;;
  esac
done
[[ "$output" == */HearthWidgets.appex ]] || { print -u2 "HEARTH_WIDGET_OUTPUT must end with /HearthWidgets.appex"; exit 1; }
version="${HEARTH_APP_VERSION:-0.1}"
number="${HEARTH_BUILD_NUMBER:-1}"
[[ "$version" =~ '^[0-9]+(\.[0-9]+){1,2}$' ]] || { print -u2 "Invalid app version"; exit 1; }
[[ "$number" =~ '^[0-9]+(\.[0-9]+){0,2}$' ]] || { print -u2 "Invalid build number"; exit 1; }
group="${HEARTH_WIDGET_APP_GROUP:-}"
[[ -z "$group" || "$group" =~ '^[A-Za-z0-9][A-Za-z0-9.-]+$' ]] || { print -u2 "Invalid app group identifier"; exit 1; }
stage="$(mktemp -d "${TMPDIR:-/tmp}/hearth-widget-build.XXXXXXXX")"
cleanup() { [[ "$stage" == "${TMPDIR:-/tmp}/hearth-widget-build."* ]] && rm -rf "$stage"; }
trap cleanup EXIT
mkdir -p "$stage/HearthWidgets.appex/Contents/MacOS"
archs=("$(uname -m)")
if [[ "$universal" == true ]]; then archs=(arm64 x86_64); fi
bins=()
for arch in "${archs[@]}"; do
  swiftc -sdk "$SDKROOT" -target "$arch-apple-macosx14.0" -parse-as-library -application-extension \
    -O -module-name HearthWidgets -file-prefix-map "$PWD=." \
    Sources/Hearth/Widgets/SharedWidgetSnapshot.swift WidgetExtension/HearthWidgets.swift \
    -o "$stage/HearthWidgets-$arch"
  lipo "$stage/HearthWidgets-$arch" -verify_arch "$arch"
  bins+=("$stage/HearthWidgets-$arch")
done
lipo -create "${bins[@]}" -output "$stage/HearthWidgets.appex/Contents/MacOS/HearthWidgets"
python3 - "$stage/HearthWidgets.appex/Contents/Info.plist" "$version" "$number" "$group" <<'PY'
import plistlib, sys
destination, version, number, group = sys.argv[1:]
info = {
    'CFBundleIdentifier': 'com.elvisobi.hearth.widgets',
    'CFBundleName': 'HearthWidgets', 'CFBundleDisplayName': 'Hearth',
    'CFBundleExecutable': 'HearthWidgets', 'CFBundlePackageType': 'XPC!',
    'CFBundleShortVersionString': version, 'CFBundleVersion': number,
    'CFBundleSupportedPlatforms': ['MacOSX'], 'LSMinimumSystemVersion': '14.0',
    'NSExtension': {'NSExtensionPointIdentifier': 'com.apple.widgetkit-extension'},
}
if group: info['HearthWidgetAppGroup'] = group
with open(destination, 'wb') as handle: plistlib.dump(info, handle)
PY
mkdir -p "${output:h}"
if [[ -e "$output" ]]; then rm -rf "$output"; fi
mv "$stage/HearthWidgets.appex" "$output"
print "Built unsigned WidgetKit extension: $output"
print "No system registration, app-group signing or gallery availability is implied."
