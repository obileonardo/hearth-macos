#!/bin/zsh
# Builds Hearth.app and installs it in ~/Applications.
#   scripts/build.sh          release build, installed
#   scripts/build.sh --debug  debug build, left in build/
#   scripts/build.sh --universal --no-install  release for Apple silicon and Intel
# HEARTH_APP_VERSION / HEARTH_BUILD_NUMBER set bundle versions; HEARTH_APP_OUTPUT
# selects the generated app path (packaging uses a private staging directory).
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/sdk.sh

config=release
install_app=true
universal=false
for arg in "$@"; do
  case "$arg" in
    --debug) config=debug; install_app=false ;;
    --no-install) install_app=false ;;
    --universal) universal=true ;;
    *) print -u2 "Usage: scripts/build.sh [--debug] [--no-install] [--universal]"; exit 1 ;;
  esac
done

app_version="${HEARTH_APP_VERSION:-0.1}"
build_number="${HEARTH_BUILD_NUMBER:-1}"
[[ "$app_version" =~ '^[0-9]+(\.[0-9]+){1,2}$' ]] || { print -u2 "Invalid HEARTH_APP_VERSION"; exit 1; }
[[ "$build_number" =~ '^[0-9]+(\.[0-9]+){0,2}$' ]] || { print -u2 "Invalid HEARTH_BUILD_NUMBER"; exit 1; }

bins=()
if [[ $universal == true ]]; then
  # New SwiftPM backends can reuse one product path for both triples. Capture
  # each slice before the next build overwrites that path.
  slice_dir="$(mktemp -d "${TMPDIR:-/tmp}/hearth-universal.XXXXXXXX")"
  cleanup_slices() {
    if [[ "$slice_dir" == "${TMPDIR:-/tmp}/hearth-universal."* ]]; then rm -rf "$slice_dir"; fi
  }
  trap cleanup_slices EXIT
  for arch in arm64 x86_64; do
    triple="$arch-apple-macosx14.0"
    swift build -c "$config" --triple "$triple" -Xswiftc -file-prefix-map -Xswiftc "$PWD=."
    built_bin="$(swift build -c "$config" --triple "$triple" --show-bin-path)/Hearth"
    lipo "$built_bin" -verify_arch "$arch"
    cp "$built_bin" "$slice_dir/Hearth-$arch"
    # Leave compiler products intact; compact only our distribution copies.
    if [[ "$config" == release ]]; then strip -S "$slice_dir/Hearth-$arch"; fi
    bins+=("$slice_dir/Hearth-$arch")
  done
else
  swift build -c "$config"
  bins+=("$(swift build -c "$config" --show-bin-path)/Hearth")
fi

app="${HEARTH_APP_OUTPUT:-build/Hearth.app}"
[[ "$app" == */Hearth.app ]] || { print -u2 "HEARTH_APP_OUTPUT must end with /Hearth.app"; exit 1; }
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
if [[ $universal == true ]]; then
  lipo -create "${bins[@]}" -output "$app/Contents/MacOS/Hearth"
else
  cp "${bins[1]}" "$app/Contents/MacOS/Hearth"
fi
# The icon is made by scripts/render-art.sh.
icon=""
if [[ -f Resources/AppIcon.icns ]]; then
  cp Resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
  icon="<key>CFBundleIconFile</key><string>AppIcon</string>"
fi
cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>com.elvisobi.hearth</string>
  <key>CFBundleName</key><string>Hearth</string>
  <key>CFBundleDisplayName</key><string>Hearth</string>
  <key>CFBundleExecutable</key><string>Hearth</string>
  $icon
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$app_version</string>
  <key>CFBundleVersion</key><string>$build_number</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>CFBundleURLTypes</key>
  <array><dict>
    <key>CFBundleURLName</key><string>com.elvisobi.hearth.widget</string>
    <key>CFBundleURLSchemes</key><array><string>hearth</string></array>
    <key>CFBundleTypeRole</key><string>Viewer</string>
  </dict></array>
  <key>NSLocalNetworkUsageDescription</key>
  <string>Hearth checks whether the gadgets you list by hand are switched on.</string>
  <key>NSAppTransportSecurity</key>
  <dict><key>NSAllowsLocalNetworking</key><true/></dict>
</dict>
</plist>
PLIST
widget_entitlements=""
if [[ "${HEARTH_INCLUDE_WIDGETKIT:-0}" == 1 ]]; then
  # Optional gallery target: desktop widgets remain the default distribution.
  widget_entitlements="${app:h}/HearthWidgetHost.entitlements"
  HEARTH_WIDGET_HOST_APP="$app" HEARTH_WIDGET_UNIVERSAL="$([[ "$universal" == true ]] && print 1 || print 0)" \
    HEARTH_WIDGET_HOST_ENTITLEMENTS="$widget_entitlements" scripts/embed-widgets.sh
fi
# Sign with an Apple Development identity when there is one, so the Keychain keeps
# trusting the app across rebuilds; otherwise sign ad hoc.
identity="${HEARTH_SIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/Apple Development/{print $2; exit}')}"
if [[ -n "$widget_entitlements" ]]; then
  if [[ "${HEARTH_WIDGET_UNSIGNED:-0}" == 1 ]]; then identity=-
  else identity="${HEARTH_WIDGET_SIGN_IDENTITY:-${HEARTH_SIGN_IDENTITY:-$identity}}"; fi
  codesign --force --sign "${identity:--}" --entitlements "$widget_entitlements" "$app"
else
  codesign --force --sign "${identity:--}" "$app"
fi

if [[ $install_app == true ]]; then
  mkdir -p ~/Applications
  rm -rf ~/Applications/Hearth.app
  cp -R "$app" ~/Applications/
  echo "Installed ~/Applications/Hearth.app"
fi
