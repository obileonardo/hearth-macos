# Public source and release status

Updated 2026-10-16. [Hearth's public repository](https://github.com/obileonardo/hearth-macos) is available from a reviewed source snapshot with independent history. The private development repository, household data and working installation remain separate. The universal preview is ad-hoc signed; a notarized Mac release still requires distribution credentials.

## Verified source and local-app delivery — 0.1.5

[Public PR #9](https://github.com/obileonardo/hearth-macos/pull/9) merged as `c4cc0f1d814c6849127e287fa6eb5f6d95b93d6f`, following the private source checks and merges. Its required [CI run 38869129008](https://github.com/obileonardo/hearth-macos/actions/runs/38869129008) passed **301 XCTest cases, two unsupported GPU skips and zero failures**, 13 maintenance fixtures, 14 release-tool fixtures and the release/contrast/shell/optional universal WidgetKit gates. The installed local app is 0.1.5 build `20261016.8`; prior app and private configuration were preserved. The owner confirmed its device tabs and final airflow, and earlier confirmed room dragging/clicks in an isolated native review.

The exact 306-file sanitized source tree and its independent public history were reviewed before publication. Source/history scans found no known leaks in scope; all 221 historical PNG blobs received metadata and local heuristic screening, and changed guides were visually reviewed with synthetic data. Scanner and media checks are not a privacy or security guarantee. Origin-bound sessions, safe credential persistence, web-session invalidation, exact-target command readback, maintenance preflight and bundled license notices were included. No private development history, operational audit, runtime data or owner recording was transferred.

**Source publication and installed delivery are complete for the recorded 0.1.5 batch.** A local 0.1.5 ad-hoc preview DMG is not published; the public download remains 0.1.3. Developer ID/notarization, gallery provisioning and the validation limits below remain separate. Newer fixes are not covered by these results until independently checked and delivered.

## Historical 0.1.3 delivery and current public download

| Area | Evidence |
|---|---|
| Public source | Final 0.1.3 batch: [public PR #7](https://github.com/obileonardo/hearth-macos/pull/7), app-source commit `1d13b39c3c42711b67dde66c67bb0c21e290f10a`, merged as `4444e00a58de912e0b398e10a320f9b107de5b41`; private PR #12 merged first from `d1b4f88700f9b97ac445e023437b5d18acd5603f` as `0f61b852be29acd419a17180f018954d376d1f56`. Independent public history retains the initial reviewed snapshot [`7f42c768`](https://github.com/obileonardo/hearth-macos/commit/7f42c768); no private development history transferred |
| Licensing and artwork | MIT license, third-party patch attribution, Apache/MIT notice files, artwork provenance and Claude/Codex assistance credits |
| Contributor onboarding | README, contribution/security guidance, issue and PR templates, generic environment examples and a release policy |
| Source hygiene | Final export of 243 files and 86 PNGs audited; credentials, runtime data, recordings, private handoff, signing profiles and generated builds excluded. Images use explicit sample data; Activity previews are memory-only with five isolated regression tests |
| Configuration | Compose uses generic `HEARTH_DATA` / `TZ` inputs; actual local configuration remains separate |
| Authentication boundaries | Artwork credentials stay at the configured Home Assistant origin; external redirects strip authorization/cookies; embedded web-session injection has an origin guard |
| Data preservation | Imports select unique scan filenames, primary-home edits preserve identity, fixture stores use explicit paths and packaging modifies a separate staged app |
| Hosted verification | [Public run 38703085752](https://github.com/obileonardo/hearth-macos/actions/runs/38703085752) passed 137 XCTest cases, two GPU-dependent skips and zero failures; release compilation, source-linked contrast, shell checks and optional universal WidgetKit compilation passed. Private PR #12 / run `38701418337` passed the same suite before public transfer |
| Repository protection | Active `main` ruleset requires pull requests and the hosted check, blocks force pushes/deletion; workflow token is read-only and checkout credentials are not persisted |
| Security reporting | Secret scanning, push protection and private vulnerability reporting enabled; support/security email is `contact@elvisobi.com` |
| Distribution tooling | Universal build, separate DMG staging, version/provenance manifest, strict signature/image/checksum verification, optional Developer ID app/image notarization and stapling |
| Download | [Universal 0.1.10](https://github.com/obileonardo/hearth-macos/releases/tag/v0.1.10), build `20261019.2`; Developer ID signed, notarized and stapled. SHA-256: `6b9e4ff935886ab43041f8a752200aaac34591c5447c7ee73a40097db4139980`. See the [verification record](release-verification-0.1.10.md). The ad-hoc-signed 0.1.1–0.1.3 previews remain as prereleases. |
| Native installation and continuity | Canonical `~/Applications/Hearth.app` updated with existing Apple Development signing to retain Keychain trust; one Hearth process verified, previous app recoverably backed up. Original working source synchronized in 41 files without changing its protected Git bookkeeping |
| Latest native UI review | Activity filter tray and translucent rounded heading card reviewed; 16pt insets, 35pt circles, Activity/Settings symbols, saved glass opacity and full content viewport without inner cutouts |
| Widgets and lighting | Interactive desktop widgets remain available; optional WidgetKit source and snapshot integration compile. Hybrid Metal contact lighting executed on an M4, with native SceneKit fallback |

The regression suite covers home/map compatibility, widget snapshots and geometry, origin/redirect boundaries, climate sequencing/recovery, appearance and navigation preferences, panel anchoring, support drafts and map-lighting guards. GPU-dependent tests skip on hosted runners without ray-tracing support. The local M4 geometry/kernel checks and hosted XCTest results are distinct evidence; neither establishes every Home Assistant device or supported OS combination.

The historical 0.1.3 implementation and preview-delivery work is complete. The release record distinguishes actual native/build checks from broader untested device, OS and assistive paths. The guarded climate retry does not claim a permanent fix for intermittent vendor rejection, and no universal frame-rate/smoothness guarantee is made. See the [0.1.3 verification record](release-verification-0.1.3.md) and [task register](../Task%20Update/README.md) for exact evidence and remaining input/vendor limits.

## Decisions in effect

Hearth is maintained by Elvis Obi. The [release policy](release-policy.md) keeps documented developer CLI tools, uses semantic versions and clearly labeled preview releases, and promises no fixed release schedule. Public source uses independent history. Product/brand names identify compatible devices; applicable third-party terms and artwork provenance remain documented.

## Remaining validation and inputs

| Area | What remains |
|---|---|
| Notarized download | Owner has offered signing access; local Developer ID Application certificate and notarization Keychain profile still need confirmation, followed by accepted app/image submissions, stapled tickets and final Gatekeeper validation |
| WidgetKit gallery | Matching macOS provisioning and App Group entitlements; registration and installed-gallery validation. This does not block desktop widgets |
| Device and OS coverage | Connected-device workflows, Intel runtime behavior, older supported macOS versions and assistive interactions require separate checks |
| Runtime operations | Container image pinning/network policy and camera-file retention require an installation-specific operational decision; source publication does not change live containers or erase personal data |
| Ongoing review | New source/assets, dependency changes, security settings and each release artifact need their own review and accurate evidence record |

See the [0.1.3 public-download verification record](release-verification-0.1.3.md), [0.1.2 history](release-verification-0.1.2.md), [0.1.1 history](release-verification-0.1.1.md), [source release preparation](source-release.md), [DMG packaging](../releases/dmg/README.md), [map lighting](map-lighting.md), [model regressions](model-regressions.md) and [security boundaries](../SECURITY.md).

## Camera help and avatar follow-up

The next source follow-up keeps camera help inside the app viewport: help centers over its control, shifts inward near either edge and moves above lower controls. Long messages are bounded, with full text retained in the control’s accessibility hint. Hover help does not intercept camera or navigation actions; information buttons also support keyboard activation and dismissal.

Avatar imports now copy and validate the new photo, GIF or video before committing its selection. A failed copy or validation preserves the previous avatar and displays an error. These changes use isolated fixtures and synthetic camera layouts; they do not require a camera command or replacing a real profile picture for testing. Their delivery evidence is separate from the historical 0.1.5 and 0.1.3 records above.
