#!/bin/zsh
# Package in a new temporary directory. Never install, launch or quit Hearth.
set -euo pipefail
cd "$(dirname "$0")/.."

usage() {
  cat <<'HELP'
Usage: scripts/package-dmg.sh [options]
  --version VERSION         Bundle version, e.g. 0.1.0 (default: 0.1.0)
  --skip-build              Package an existing universal build/Hearth.app
  --app PATH                Existing app to package; implies --skip-build
  --preview                 Ad-hoc local preview; never a notarized release
  --identity IDENTITY       Developer ID Application name or certificate SHA-1
  --notary-profile PROFILE  Existing notarytool Keychain profile; notarize + staple
  --help                    Show this help

No identity defaults to preview mode. An identity without a notary profile produces
a signed-unnotarized image. The script never stores or accepts account passwords.
HELP
}
fail() { print -u2 -- "Packaging stopped: $*"; exit 1; }

version=0.1.0
skip_build=false
preview=false
identity=""
notary_profile=""
source_app=build/Hearth.app
while (( $# > 0 )); do
  case "$1" in
    --version|--app|--identity|--notary-profile)
      (( $# >= 2 )) || fail "Missing value for $1"
      [[ -n "$2" && "$2" != --* ]] || fail "Missing value for $1"
      case "$1" in
        --version) version="$2" ;;
        --app) source_app="$2"; skip_build=true ;;
        --identity) identity="$2" ;;
        --notary-profile) notary_profile="$2" ;;
      esac
      shift 2 ;;
    --skip-build) skip_build=true; shift ;;
    --preview) preview=true; shift ;;
    --help|-h) usage; exit 0 ;;
    *) usage; fail "Unknown option: $1" ;;
  esac
done
[[ "$version" =~ '^[0-9]+(\.[0-9]+){1,2}$' ]] || fail "Version must contain two or three numeric components"
build_number="${HEARTH_BUILD_NUMBER:-1}"
[[ "$build_number" =~ '^[0-9]+(\.[0-9]+){0,2}$' ]] || fail "Invalid HEARTH_BUILD_NUMBER"
if [[ -z "$identity" ]]; then preview=true; fi
if [[ $preview == true ]]; then
  [[ -z "$identity" && -z "$notary_profile" ]] || fail "Preview cannot use an identity or notary profile"
  mode=preview-ad-hoc
  suffix=-PREVIEW
  release_note="LOCAL PREVIEW — ad-hoc signed, not notarized. This is not a public distribution build."
else
  [[ "$identity" == "Developer ID Application:"* || "$identity" =~ '^[A-Fa-f0-9]{40}$' ]] || \
    fail "Use a Developer ID Application identity, not Apple Development or Mac Distribution"
  if [[ -n "$notary_profile" ]]; then
    mode=developer-id-notarized
    suffix=""
    release_note="Developer ID signed. This image is released only after Apple's notarization is accepted and its ticket is stapled and validated."
  else
    mode=developer-id-unnotarized
    suffix=-signed-unnotarized
    release_note="SIGNED, NOT NOTARIZED — this is not the completed public distribution build."
  fi
fi

filename="Hearth-${version}-universal${suffix}.dmg"
output_dir="$PWD/releases/dmg"
final_image="$output_dir/$filename"
[[ ! -e "$final_image" && ! -e "$final_image.sha256" ]] || fail "Output already exists: $filename"
mkdir -p "$output_dir"
work_dir="$(mktemp -d "${TMPDIR:-/tmp}/hearth-dmg.XXXXXXXX")"
cleanup() {
  # Only the directory made by this invocation is ever removed.
  if [[ -n "$work_dir" && "$work_dir" == "${TMPDIR:-/tmp}/hearth-dmg."* ]]; then
    rm -rf "$work_dir"
  fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

if [[ $skip_build == false ]]; then
  source_app="$work_dir/build/Hearth.app"
  HEARTH_APP_OUTPUT="$source_app" HEARTH_APP_VERSION="$version" \
    HEARTH_BUILD_NUMBER="$build_number" HEARTH_SIGN_IDENTITY=- \
    scripts/build.sh --universal --no-install
fi
[[ -f "$source_app/Contents/Info.plist" && -f "$source_app/Contents/MacOS/Hearth" ]] || fail "Hearth.app is incomplete"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$source_app/Contents/Info.plist")" == com.elvisobi.hearth ]] || fail "Unexpected app identifier"
minimum_system="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$source_app/Contents/Info.plist")"
[[ "$minimum_system" =~ '^[0-9]+(\.[0-9]+){1,2}$' ]] || fail "Invalid minimum macOS version"
for arch in arm64 x86_64; do
  lipo "$source_app/Contents/MacOS/Hearth" -verify_arch "$arch" || fail "The app must contain both arm64 and x86_64"
done

python3 scripts/bundle-notices.py "$source_app" --verify || fail "App license notices are missing or stale; rebuild before packaging"

payload="$work_dir/payload"
staged_app="$payload/Hearth.app"
mkdir -p "$staged_app/Contents/MacOS" "$staged_app/Contents/Resources"
# The bundle contains the executable, plist, icon and exact reviewed license notices.
# Reject unexpected payload files instead of silently including private material or dropping features.
while IFS= read -r item; do
  relative="${item#"$source_app/"}"
  case "$relative" in
    Contents/Info.plist|Contents/MacOS/Hearth|Contents/Resources/AppIcon.icns|Contents/Resources/LICENSE|Contents/Resources/THIRD_PARTY_NOTICES.md|Contents/Resources/docs/licenses/Apache-2.0.txt|Contents/Resources/docs/licenses/eufy-security-client-MIT.txt|Contents/_CodeSignature/*) ;;
    *) fail "Unexpected bundle file: $relative. Review packaging before adding a new resource." ;;
  esac
done < <(find "$source_app" -type f)
cp "$source_app/Contents/Info.plist" "$staged_app/Contents/Info.plist"
cp "$source_app/Contents/MacOS/Hearth" "$staged_app/Contents/MacOS/Hearth"
if [[ -f "$source_app/Contents/Resources/AppIcon.icns" ]]; then
  cp "$source_app/Contents/Resources/AppIcon.icns" "$staged_app/Contents/Resources/AppIcon.icns"
fi
python3 scripts/bundle-notices.py "$staged_app"
python3 scripts/bundle-notices.py "$staged_app" --verify
chmod 755 "$staged_app/Contents/MacOS/Hearth"
# All modifications affect the staged copy, never the supplied/running app.
strip -S "$staged_app/Contents/MacOS/Hearth"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $version" "$staged_app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $build_number" "$staged_app/Contents/Info.plist"
xattr -cr "$staged_app"

if [[ $preview == true ]]; then
  codesign --force --sign - "$staged_app"
else
  codesign --force --options runtime --timestamp --sign "$identity" "$staged_app"
  signing_details="$(codesign --display --verbose=4 "$staged_app" 2>&1)"
  [[ "$signing_details" == *"Authority=Developer ID Application:"* ]] || fail "The certificate is not Developer ID Application"
  [[ "$signing_details" == *"(runtime)"* && "$signing_details" == *"Timestamp="* ]] || fail "Hardened runtime or secure timestamp is missing"
fi
codesign --verify --deep --strict "$staged_app"

source_commit="${HEARTH_SOURCE_COMMIT:-$(git rev-parse HEAD 2>/dev/null || print unknown)}"
[[ "$source_commit" == unknown || "$source_commit" =~ '^[A-Fa-f0-9]{7,40}$' ]] || fail "Invalid HEARTH_SOURCE_COMMIT"
source_state=clean
if [[ -n "$(git status --porcelain --untracked-files=normal 2>/dev/null)" ]]; then source_state=modified; fi
cat > "$payload/BuildInfo.txt" <<INFO
Hearth $version ($build_number)
Source commit: $source_commit
Source working tree: $source_state
Input: $([[ $skip_build == true ]] && print supplied-universal-app || print release-universal-build)
Architectures: arm64, x86_64
Minimum supported macOS: $minimum_system
Signing mode: $mode
$release_note
INFO
cat > "$payload/Install Hearth.txt" <<INFO
Hearth $version

$release_note

To install:
1. Drag Hearth.app to Applications.
2. Open Hearth from Applications. Its controls appear in the menu bar.
3. Connect your Home Assistant instance in Hearth Settings.
4. Eject this disk image after copying the app.

This image contains the app, an Applications shortcut and these instructions.
The app includes LICENSE, THIRD_PARTY_NOTICES.md and the referenced upstream
license texts in Contents/Resources. These notices remain with the installed copy.
It contains no account credentials, saved homes, camera history or personal settings.
Installing is your choice: creating this image does not change a running or installed Hearth.
The preview and signed-unnotarized variants may be blocked by macOS Gatekeeper.
Use a completed notarized release for normal distribution.
INFO
ln -s /Applications "$payload/Applications"

if [[ -n "$notary_profile" ]]; then
  # Staple the app as well as its disk image so the installed copy carries its
  # own ticket after it is dragged out of the image and the image is ejected.
  ditto -c -k --sequesterRsrc --keepParent "$staged_app" "$work_dir/Hearth.zip"
  xcrun notarytool submit "$work_dir/Hearth.zip" --keychain-profile "$notary_profile" \
    --wait --output-format json > "$work_dir/app-notary-result.json"
  app_notary_status="$(plutil -extract status raw -o - "$work_dir/app-notary-result.json")"
  [[ "$app_notary_status" == Accepted ]] || fail "App notarization was not accepted ($app_notary_status)"
  xcrun stapler staple "$staged_app"
  xcrun stapler validate "$staged_app"
  spctl --assess --type execute --verbose=2 "$staged_app"
fi

image="$work_dir/$filename"
# macOS 26+ moved creation to DiskImages2. Its supported folder path avoids a
# legacy hdiutil/HFS+ creation stall observed on current macOS installations.
# Retain hdiutil for older supported systems where the new subcommand is absent.
if diskutil image create from --help >/dev/null 2>&1; then
  diskutil image create from --format UDZO --volumeName "Hearth $version" "$payload" "$image"
else
  hdiutil create -srcfolder "$payload" -volname "Hearth $version" \
    -format UDZO -fs HFS+ -nospotlight -srcowners off "$image"
fi
hdiutil verify "$image"
if [[ $preview == false ]]; then
  codesign --force --timestamp --sign "$identity" "$image"
  codesign --verify --strict "$image"
fi
if [[ -n "$notary_profile" ]]; then
  # Capture results privately; a failed or rejected submission never reaches releases/dmg.
  xcrun notarytool submit "$image" --keychain-profile "$notary_profile" \
    --wait --output-format json > "$work_dir/notary-result.json"
  notary_status="$(plutil -extract status raw -o - "$work_dir/notary-result.json")"
  [[ "$notary_status" == Accepted ]] || fail "Notarization was not accepted ($notary_status)"
  xcrun stapler staple "$image"
  xcrun stapler validate "$image"
  spctl --assess --type open --context context:primary-signature --verbose=2 "$image"
fi
digest="$(shasum -a 256 "$image" | awk '{print $1}')"
print -r -- "$digest  $filename" > "$work_dir/$filename.sha256"
# Never overwrite an existing release, even if another invocation finished while this one ran.
mv -n "$image" "$final_image"
[[ ! -e "$image" ]] || fail "A release with this name appeared during packaging"
mv -n "$work_dir/$filename.sha256" "$final_image.sha256"
[[ ! -e "$work_dir/$filename.sha256" ]] || fail "The checksum output already exists"
print -r -- "Created $final_image"
print -r -- "SHA-256: $digest"
print -r -- "$release_note"
