# Hearth 0.1.8 verification

Recorded 18 October 2026. [Download and release notes](https://github.com/obileonardo/hearth-macos/releases/tag/v0.1.8).

0.1.8 is the first Developer ID signed and Apple-notarized download. It collects the source changes since the 0.1.3 preview (see the [changelog](../CHANGELOG.md)), including the fan AUTO key, quicker climate-mode confirmation, longer camera-refresh and rotation choices, the Rooms floor menu fix and an alert capsule 16 points below the drawn status pill. The table describes this artifact and its observed checks.

| Check | Result |
|---|---|
| Recorded source | `17e07682201241c98f7fc2e8c0a3c5137a3032d6` (private PR #22 merge), clean working tree, recorded in `BuildInfo.txt`; version 0.1.8, build `20261017.2` |
| Source provenance | `Sources`, `Tests`, `scripts` and `Package.swift` in this repository are identical to the recorded source; the public PR carrying the alert change was compared file by file before publication |
| Hosted checks | Private PR #22 run `39059727829`: 345 XCTest cases, two GPU-dependent skips, zero failures. The public PR carrying the same code runs the same required checks before merge |
| Universal app | arm64 and x86_64 slices present; macOS 14 deployment target retained |
| Signing | `Developer ID Application: Obi Elvis (DD8UY75RZT)`, hardened runtime, secure timestamp; strict/deep signature verification passed |
| Notarization | App and disk-image submissions both `Accepted` by Apple's notary service; tickets stapled to both and validated |
| Gatekeeper | Disk image and the app inside it assessed as `accepted`, source `Notarized Developer ID` |
| Disk image | Embedded integrity checks passed; mounted read-only, payload reviewed and detached |
| Payload | Only Hearth.app, an Applications shortcut, installation instructions and BuildInfo.txt. The bundle holds the executable, plist, icon, signature, LICENSE, THIRD_PARTY_NOTICES.md and the referenced license texts. No personal configuration, recordings, camera pictures, histories, credentials or signing material |
| Executable paths | Owner home and external-drive absolute paths absent from the executable |
| SHA-256 | `7120c2b5821b80809db66fcf0a4a14c21d7a445c514f12fc08520b209c75d021` |
| Local installation | The same source was installed as the maintainer's 0.1.8 (build `20261017.2`); the maintainer confirmed the 0.1.7 checks (Rooms floor menu, demo-home motion, AC confirmation) and the restored notification icon |

The unprovisioned WidgetKit gallery extension is omitted; desktop widgets remain available. No certificate, private key, password or notarization profile is included in source or the disk image.

These checks do not certify Intel runtime behavior, every supported macOS version, full VoiceOver coverage, all physical integrations or a complete security audit. Hosted GPU skips remain explicit. Pairing, vendor capabilities and operational policies remain separate requirements.

The ad-hoc-signed [0.1.3](release-verification-0.1.3.md), [0.1.2](release-verification-0.1.2.md) and [0.1.1](release-verification-0.1.1.md) preview records are retained as history. Later documentation-only commits do not change the disk image's recorded source identity.
