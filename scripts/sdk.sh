#!/bin/zsh
# Shared by the build and artwork scripts. Respect an explicitly selected SDK.
if [[ -n "${HEARTH_SDKROOT:-}" ]]; then
  export SDKROOT="$HEARTH_SDKROOT"
elif [[ -z "${SDKROOT:-}" ]]; then
  detected_sdk="$(xcrun --sdk macosx --show-sdk-path)"
  # This CLT's macOS 27 SwiftUI macros need full Xcode. Keep the known working
  # 26.5 SDK when it is installed alongside it, without assuming a toolchain path.
  compatible_sdk="${detected_sdk:h}/MacOSX26.5.sdk"
  if [[ "$detected_sdk" == */CommandLineTools/* && -d "$compatible_sdk" ]]; then
    export SDKROOT="$compatible_sdk"
  else
    export SDKROOT="$detected_sdk"
  fi
fi
if [[ ! -d "$SDKROOT" ]]; then
  print -u2 "SDK not found: $SDKROOT. Select an installed SDK with HEARTH_SDKROOT."
  exit 1
fi
