#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/sdk.sh
stage="$(mktemp -d "${TMPDIR:-/tmp}/hearth-widget-preview.XXXXXXXX")"
cleanup() { [[ "$stage" == "${TMPDIR:-/tmp}/hearth-widget-preview."* ]] && rm -rf "$stage"; }
trap cleanup EXIT
swiftc -sdk "$SDKROOT" -target "$(uname -m)-apple-macosx14.0" -parse-as-library \
  -D HEARTH_WIDGET_PREVIEW -module-name HearthWidgetPreview \
  Sources/Hearth/Widgets/SharedWidgetSnapshot.swift WidgetExtension/HearthWidgets.swift WidgetExtension/Preview.swift \
  -o "$stage/WidgetPreview"
"$stage/WidgetPreview" "${1:-/private/tmp/hearth-widget-gallery-previews}"
