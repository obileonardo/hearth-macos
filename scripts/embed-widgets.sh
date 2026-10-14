#!/bin/zsh
# Optional opt-in for a staging app. Never installs/registers the result.
set -euo pipefail
cd "$(dirname "$0")/.."
app="${HEARTH_WIDGET_HOST_APP:?Set HEARTH_WIDGET_HOST_APP to the staging Hearth.app}"
[[ "$app" == */Hearth.app && -f "$app/Contents/Info.plist" ]] || { print -u2 "Expected a built staging Hearth.app"; exit 1; }
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist")" == com.elvisobi.hearth ]] || { print -u2 "Unexpected host bundle identifier"; exit 1; }
group="${HEARTH_WIDGET_APP_GROUP:-}"
unsigned="${HEARTH_WIDGET_UNSIGNED:-0}"
identity="${HEARTH_WIDGET_SIGN_IDENTITY:-${HEARTH_SIGN_IDENTITY:-}}"
if [[ "$unsigned" != 1 ]]; then
  [[ -n "$group" && -n "$identity" && "$identity" != - ]] || { print -u2 "Signed WidgetKit builds require HEARTH_WIDGET_APP_GROUP and HEARTH_WIDGET_SIGN_IDENTITY"; exit 1; }
  [[ -f "${HEARTH_WIDGET_PROFILE:-}" && -f "${HEARTH_HOST_PROFILE:-}" ]] || { print -u2 "Provide matching macOS HEARTH_WIDGET_PROFILE and HEARTH_HOST_PROFILE"; exit 1; }
fi
stage="$(mktemp -d "${TMPDIR:-/tmp}/hearth-widget-embed.XXXXXXXX")"
cleanup() { [[ "$stage" == "${TMPDIR:-/tmp}/hearth-widget-embed."* ]] && rm -rf "$stage"; }
trap cleanup EXIT
args=()
[[ "${HEARTH_WIDGET_UNIVERSAL:-0}" == 1 ]] && args+=(--universal)
HEARTH_WIDGET_OUTPUT="$stage/HearthWidgets.appex" scripts/build-widgets.sh "${args[@]}"
if [[ "$unsigned" == 1 ]]; then
  cp WidgetExtension/HearthWidgets.entitlements "$stage/extension.entitlements"
  print '<?xml version="1.0"?><plist version="1.0"><dict/></plist>' > "$stage/host.entitlements"
  codesign --force --sign - --entitlements "$stage/extension.entitlements" "$stage/HearthWidgets.appex"
else
  security cms -D -i "$HEARTH_WIDGET_PROFILE" -o "$stage/extension-profile.plist"
  security cms -D -i "$HEARTH_HOST_PROFILE" -o "$stage/host-profile.plist"
  python3 scripts/widget-signing-inputs.py "$stage" "$group"
  cp "$HEARTH_WIDGET_PROFILE" "$stage/HearthWidgets.appex/Contents/embedded.provisionprofile"
  codesign --force --sign "$identity" --entitlements "$stage/extension.entitlements" "$stage/HearthWidgets.appex"
fi
python3 - "$app/Contents/Info.plist" "$group" <<'PY'
import plistlib, sys
path, group = sys.argv[1:]
with open(path, 'rb') as handle: info = plistlib.load(handle)
if group: info['HearthWidgetAppGroup'] = group
else: info.pop('HearthWidgetAppGroup', None)
with open(path, 'wb') as handle: plistlib.dump(info, handle)
PY
mkdir -p "$app/Contents/PlugIns"
destination="$app/Contents/PlugIns/HearthWidgets.appex"
if [[ -e "$destination" ]]; then rm -rf "$destination"; fi
ditto "$stage/HearthWidgets.appex" "$destination"
if [[ "$unsigned" != 1 ]]; then cp "$HEARTH_HOST_PROFILE" "$app/Contents/embedded.provisionprofile"; fi
host_entitlements="${HEARTH_WIDGET_HOST_ENTITLEMENTS:-${app:h}/HearthWidgetHost.entitlements}"
cp "$stage/host.entitlements" "$host_entitlements"
print "Prepared optional WidgetKit extension in staging app. Host must be signed with $host_entitlements."
