# Hearth 0.1.2 preview verification

Recorded 14 October 2026. Download: [versioned GitHub prerelease](https://github.com/obileonardo/hearth-macos/releases/tag/v0.1.2-preview).

This preview delivers the adaptive blue appearance, native menu-panel anchoring, selected navigation glyphs, revised Settings and Help layouts, immediate destination transitions, and speaker action routing reviewed for this release. Later UI feedback received at 11:01 is queued separately and is not included.

| Check | Result |
|---|---|
| Reviewed public app source | `accbedca5492976cffe098b4ec27707849b95296`, recorded in the packaged `BuildInfo.txt` |
| Source provenance | App sources match the reviewed implementation `b76ffb2`; private development history and runtime stores are excluded from the public export |
| Publication | Public PR #2 merged as `9d285de36179ca88be94cc27da2cb4808740461f`; the release binary remains tied to the reviewed app-source commit above |
| Hosted public checks | [Public run 38549884465](https://github.com/obileonardo/hearth-macos/actions/runs/38549884465): 57 XCTest cases, two GPU-dependent skips and zero failures; release build, shell checks and optional universal WidgetKit compile passed |
| Hosted private checks | Private run `38547523275` passed the same 57-case suite with two GPU-dependent skips and zero failures; private PR #7 merged before public source synchronization |
| Universal binary | arm64 and x86_64 architectures verified; macOS 14 deployment target retained |
| App signature | Strict/deep ad-hoc signature verification passed; not Developer ID signed or notarized |
| Disk image | Integrity checks passed; mounted read-only and reviewed |
| Payload | Only `Hearth.app`, an Applications shortcut, installation instructions and `BuildInfo.txt`; no personal configuration, transcripts, homes, face samples or camera history |
| Packaged SHA-256 | `8b100910bdc7ec4a352bce41843be2376f5173ca279db10487b117d0f2b2b7b1` |
| Public download | Fresh unauthenticated GitHub download matched the packaged SHA-256 and published checksum |
| Native UI review | Native panel and Light appearance were reviewed in the development candidate with existing saved data; panel remained open through native in-app dialogs. The final universal bundle launched, but its final UI review remains incomplete because native automation timed out |
| Speaker playback review | Approved local playback was confirmed by Home Assistant and heard by the owner; this is one local integration check, not general vendor certification |
| Documentation images | Offline reserved fixtures only; all ten light/dark guides, both native device showpieces and the demo map were visually inspected; no unsupported-control placeholders or personal data observed |

The guide exporter uses explicit static illustrations for sign-in fields and the Help version-information switch because offscreen rendering cannot capture those native controls. The normal app keeps its native interactive controls. This provenance is disclosed in the README; screenshot readings and device states are examples.

The preview omits the unprovisioned WidgetKit extension. Its optional universal build passed, but gallery registration still requires valid host/extension provisioning, an App Group and signing credentials. Existing in-app desktop widgets remain available.

The release is ad-hoc signed and **not notarized**. A Developer ID signed and notarized download needs the maintainer's local Developer ID Application certificate and notarization Keychain profile. Certificates, private keys and passwords stay outside the repository.

These checks do not establish Intel runtime behavior, all supported macOS releases, full VoiceOver coverage, a complete security audit or compatibility with every physical device. Hosted GPU skips remain explicit; successful local checks and one heard playback session do not replace that broader coverage.

The [0.1.1 verification record](release-verification-0.1.1.md) remains unchanged as release history. Later documentation commits or source changes do not alter this DMG's recorded source identity.
