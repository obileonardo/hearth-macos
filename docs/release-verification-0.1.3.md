# Hearth 0.1.3 preview verification

Recorded 15 October 2026. [Download and release notes](https://github.com/obileonardo/hearth-macos/releases/tag/v0.1.3-preview).

This preview includes translucent floating navigation and heading cards, remembered glass opacity, 16-point heading insets and smaller overlapping illustrations, a full-panel scroll viewport, an equal-width Activity filter tray, Assets, stable open-panel placement, refined solar/console artwork, clearer support drafts and climate command sequencing/recovery. The table describes this artifact and its observed checks.

| Check | Result |
|---|---|
| Reviewed public app source | `1d13b39c3c42711b67dde66c67bb0c21e290f10a`, recorded in `BuildInfo.txt`; version 0.1.3, build `20261015.5` |
| Source provenance | Production inputs match reviewed private implementation `d1b4f88700f9b97ac445e023437b5d18acd5603f`; 243 allowlisted files reviewed, independent public history, no runtime stores or private development history transferred |
| Private publication | PR #12 merged as `0f61b852be29acd419a17180f018954d376d1f56` before public transfer |
| Public publication | [PR #7](https://github.com/obileonardo/hearth-macos/pull/7) merged as `4444e00a58de912e0b398e10a320f9b107de5b41`; the release tag points to this merge |
| Hosted public checks | [Run 38703085752](https://github.com/obileonardo/hearth-macos/actions/runs/38703085752): 137 XCTest cases, two GPU-dependent skips, zero failures; release compilation, contrast, shell syntax and optional universal WidgetKit compilation passed |
| Hosted private checks | Run `38701418337` passed the same 137-case suite, with two GPU-dependent skips and zero failures, plus release/contrast/shell/WidgetKit checks |
| Universal app | arm64 and x86_64 verified separately; macOS 14 deployment target retained |
| Public app signature | Strict/deep ad-hoc signature verification passed; not Developer ID signed or notarized |
| Disk image | Embedded integrity checks passed; mounted read-only, payload/provenance checked and detached |
| Payload | Only Hearth.app, an Applications shortcut, installation instructions and BuildInfo.txt; bundle contains the executable, plist, icon and signature. No personal configuration, recordings, camera pictures, histories or signing profiles |
| Executable paths | Owner home/external-drive absolute paths absent from the staged executable |
| SHA-256 | `9c0b1608d4d49557a1cbe963562d83d00bf9dafaf528a03aef3f034641c2e78a` |
| Public download | A fresh unauthenticated download matched both the packaged SHA-256 and published checksum. |
| Local installation | Canonical application updated to 0.1.3 build 20261015.5; strict signature and both architecture UUIDs checked against the staged source build. Existing local development signing preserves Keychain trust; one canonical process runs. Prior app recoverably archived |
| Native UI review | Review candidates showed the Activity filter tray, translucent heading, smaller icons, 16-point margins and content scrolling behind glass without the inner cutout. Security scroll/return and Assets → demo home → Back were reviewed during this cycle. This is separate from full VoiceOver or cross-machine coverage |
| Documentation privacy | 86 PNGs metadata-reviewed; only dimensions, color-space and resolution EXIF. New Activity examples use explicit in-memory synthetic events; image/camera/face references are stripped and live attachment, persistence and notification work are blocked. Five isolation regressions passed |
| Image provenance | Actual app components with offline fixtures. Sign-in/draft fields, switches, navigation slider and glass use explicitly documented static offscreen fallbacks; native interactive behavior remains in the running app |

The unprovisioned WidgetKit gallery extension is omitted. Its optional universal compile passed; gallery activation still needs matching host/extension provisioning and an App Group. Existing desktop widgets remain available.

The public preview is **ad-hoc signed and not notarized**. A Developer ID Application certificate and local notarization Keychain profile remain pending from the maintainer. No certificate, private key, password or profile is included in source or the DMG.

Climate recovery performs one retry only for the observed vendor rejection after fresh-state checks. A changed power/mode state or unrelated error prevents blind retry. Persistent errors remain visible; successful fixtures and limited approved live checks do not establish a permanent vendor fix.

These checks do not certify Intel runtime behavior, every supported macOS version, full VoiceOver coverage, all physical integrations, universal frame-rate/smoothness or a complete security audit. Hosted GPU skips remain explicit. Pairing, vendor capabilities and operational policies remain separate requirements.

[0.1.2 verification](release-verification-0.1.2.md) and [0.1.1 verification](release-verification-0.1.1.md) are retained as history. Later documentation-only commits do not change the DMG's recorded source identity.
