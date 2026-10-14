#!/bin/zsh
# Renders the device illustrations, app icon and menu bar glyph to PNGs, and builds
# Resources/AppIcon.icns from the icon.
#   scripts/render-art.sh          writes to docs/art
#   scripts/render-art.sh <dir>    writes somewhere else
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/sdk.sh

out="${1:-docs/art}"
mkdir -p "$out"
out="$(cd "$out" && pwd)"

swift build
"$(swift build --show-bin-path)/Hearth" --render-art "$out"

# Every size macOS asks for, from 16 to 1024, at 1x and 2x.
work="$(mktemp -d)"
iconset="$work/AppIcon.iconset"
mkdir -p "$iconset"
for s in 16 32 128 256 512; do
  sips -z $s $s "$out/AppIcon-1024.png" --out "$iconset/icon_${s}x${s}.png" >/dev/null
  sips -z $((s * 2)) $((s * 2)) "$out/AppIcon-1024.png" --out "$iconset/icon_${s}x${s}@2x.png" >/dev/null
done
mkdir -p Resources
iconutil -c icns "$iconset" -o Resources/AppIcon.icns
rm -rf "$work"
echo "Icon written to Resources/AppIcon.icns"
