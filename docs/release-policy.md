# Release and maintenance policy

Hearth is maintained by Elvis Obi. Support and private security reports go to contact@elvisobi.com; see SECURITY.md for what to include. Contributions use the MIT license, with applicable third-party terms listed separately.

## Versions and distribution

Use semantic versions and versioned GitHub Releases. Preview releases must be clearly marked as prereleases; an ad-hoc-signed preview must never be presented as notarized. A verified Mac download requires Developer ID Application signing, accepted notarization, stapled tickets and an accompanying SHA-256 checksum. Ship after source review, hosted build/regressions and the relevant manual checks; no fixed release schedule is promised.

The source targets macOS 14 or later. Newer APIs use availability guards. The hosted build covers its installed macOS/Xcode version; support on every older OS and every Home Assistant integration requires separate validation. Home Assistant provides the state/command capability; unavailable vendor functions remain unavailable.

Existing developer CLI tools remain available and documented. They only act when explicitly invoked and may use the user's authenticated Home Assistant session. Do not publish credentials or run copied commands against live devices without understanding them.

## Preserve installations

Source publication uses reviewed files and independent public history. Keep private development history, runtime files, camera/face data, settings and credentials separate and intact. Normal builds and packaging must not silently change live Home Assistant containers, pairing, network policy or personal-data retention.

## Verification records

Record the source commit, architecture, build/test results, signing/notarization status, artifact checksum and known hardware/toolchain limits for each release. Fixture and simulation checks cannot be described as successful physical-device tests. Optional WidgetKit extension distribution requires its own provisioning and App Group validation; desktop widgets remain available.
