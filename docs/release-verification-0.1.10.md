# Hearth 0.1.10 verification

Recorded 19 October 2026. [Download and release notes](https://github.com/obileonardo/hearth-macos/releases/tag/v0.1.10).

0.1.10 places the menu-bar alert 12 points below the status pill. In earlier releases macOS moved the alert's clear window below the menu bar as it appeared, which added a full menu bar to the gap; the window now stays where it is placed. See the [changelog](../CHANGELOG.md). The table describes this artifact and its observed checks.

| Check | Result |
|---|---|
| Recorded source | `dcb0879e7e1eb5f8f03f9cea6541cba3d6fcef13` (private PR #24 merge), clean working tree, recorded in `BuildInfo.txt`; version 0.1.10, build `20261019.2` |
| Source provenance | `Sources`, `Tests`, `scripts` and `Package.swift` in this repository are identical to the recorded source; compared file by file before publication |
| Hosted checks | Private PR #24 run `39256825187`: 346 XCTest cases, two GPU-dependent skips, zero failures, including `testShownFlashPanelKeepsItsMenuBarOverlap`, which shows a real panel and checks its frame. The public PR carrying the same code runs the same required checks before merge |
| On-screen placement | On the maintainer's display (30-point menu bar), the installed build's alert window measured 2 points from the screen top, putting the capsule exactly 12 points under the status pill |
| Universal app | arm64 and x86_64 slices present; macOS 14 deployment target retained |
| Signing | `Developer ID Application: Obi Elvis (DD8UY75RZT)`, hardened runtime, secure timestamp; strict/deep signature verification passed |
| Notarization | App and disk-image submissions both `Accepted` by Apple's notary service; tickets stapled to both and validated |
| Gatekeeper | Disk image and the app inside it assessed as `accepted`, source `Notarized Developer ID` |
| Disk image | Embedded integrity checks passed; mounted read-only, payload reviewed and detached |
| Payload | Only Hearth.app, an Applications shortcut, installation instructions and BuildInfo.txt. The bundle holds the executable, plist, icon, signature, LICENSE, THIRD_PARTY_NOTICES.md and the referenced license texts. No personal configuration, recordings, camera pictures, histories, credentials or signing material |
| Executable paths | Owner home and external-drive absolute paths absent from the executable |
| SHA-256 | `6b9e4ff935886ab43041f8a752200aaac34591c5447c7ee73a40097db4139980` |

The unprovisioned WidgetKit gallery extension is omitted; desktop widgets remain available. No certificate, private key, password or notarization profile is included in source or the disk image.

These checks do not certify Intel runtime behavior, every supported macOS version, full VoiceOver coverage, all physical integrations or a complete security audit. Hosted GPU skips remain explicit. Pairing, vendor capabilities and operational policies remain separate requirements.

The [0.1.8 record](release-verification-0.1.8.md) and the ad-hoc-signed [0.1.3](release-verification-0.1.3.md), [0.1.2](release-verification-0.1.2.md) and [0.1.1](release-verification-0.1.1.md) preview records are retained as history. Later documentation-only commits do not change the disk image's recorded source identity.
