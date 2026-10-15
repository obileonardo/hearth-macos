# Public source and release status

Updated 2026-10-15. [Hearth's public repository](https://github.com/obileonardo/hearth-macos) is available from a reviewed source snapshot with independent history. The private development repository, household data and working installation remain separate. The universal preview is ad-hoc signed; a notarized Mac release still requires distribution credentials.

## Completed

| Area | Evidence |
|---|---|
| Public source | Latest completed batch: [public PR #6](https://github.com/obileonardo/hearth-macos/pull/6), app-source commit `e7fc0f61dc596cd70b37f4829e32a53613bb0711`, merged as `2161d69647d822a9153c0bdea5c786178e31b71d`; private PR #11 merged first. Independent public history retains the initial reviewed snapshot [`7f42c768`](https://github.com/obileonardo/hearth-macos/commit/7f42c768); no private development history transferred |
| Licensing and artwork | MIT license, third-party patch attribution, Apache/MIT notice files, artwork provenance and Claude/Codex assistance credits |
| Contributor onboarding | README, contribution/security guidance, issue and PR templates, generic environment examples and a release policy |
| Source hygiene | Reviewed export excludes credentials, runtime data, recordings, private handoff, signing profiles and generated builds; included screenshots use explicit sample data |
| Configuration | Compose uses generic `HEARTH_DATA` / `TZ` inputs; actual local configuration remains separate |
| Authentication boundaries | Artwork credentials stay at the configured Home Assistant origin; external redirects strip authorization/cookies; embedded web-session injection has an origin guard |
| Data preservation | Imports select unique scan filenames, primary-home edits preserve identity, fixture stores use explicit paths and packaging modifies a separate staged app |
| Hosted verification | [Latest public run](https://github.com/obileonardo/hearth-macos/actions/runs/38696784897) passed 129 XCTest cases, two GPU-dependent skips and zero failures; release compilation, source-linked contrast, shell checks and optional universal WidgetKit compilation passed. Private PR #11 passed the same suite before public transfer |
| Repository protection | Active `main` ruleset requires pull requests and the hosted check, blocks force pushes/deletion; workflow token is read-only and checkout credentials are not persisted |
| Security reporting | Secret scanning, push protection and private vulnerability reporting enabled; support/security email is `contact@elvisobi.com` |
| Distribution tooling | Universal build, separate DMG staging, version/provenance manifest, strict signature/image/checksum verification, optional Developer ID app/image notarization and stapling |
| Preview download | [Universal 0.1.2 preview](https://github.com/obileonardo/hearth-macos/releases/tag/v0.1.2-preview), public app-source `accbedca5492976cffe098b4ec27707849b95296`; verified and ad-hoc signed, not notarized. SHA-256: `8b100910bdc7ec4a352bce41843be2376f5173ca279db10487b117d0f2b2b7b1`. The latest source batch is not included in this DMG |
| Widgets and lighting | Interactive desktop widgets remain available; optional WidgetKit source and snapshot integration compile. Hybrid Metal contact lighting executed on an M4, with native SceneKit fallback |

The regression suite covers home/map compatibility, widget snapshots and geometry, origin/redirect boundaries, climate sequencing/recovery, appearance and navigation preferences, panel anchoring, support drafts and map-lighting guards. GPU-dependent tests skip on hosted runners without ray-tracing support. The local M4 geometry/kernel checks and hosted XCTest results are distinct evidence; neither establishes every Home Assistant device or supported OS combination.

The next heading-card refinement is in progress after the merged batch. A final 0.1.3 universal build, native review, artifact verification and public DMG publication remain pending. Current source availability is separate from the released download. See the [task register](../Task%20Update/README.md) for the current work and genuine input/vendor limits.

## Decisions in effect

Hearth is maintained by Elvis Obi. The [release policy](release-policy.md) keeps documented developer CLI tools, uses semantic versions and clearly labeled preview releases, and promises no fixed release schedule. Public source uses independent history. Product/brand names identify compatible devices; applicable third-party terms and artwork provenance remain documented.

## Remaining validation and inputs

| Area | What remains |
|---|---|
| Notarized download | Developer ID Application certificate and a local notarization Keychain profile; accepted app/image submissions, stapled tickets and final Gatekeeper validation |
| WidgetKit gallery | Matching macOS provisioning and App Group entitlements; registration and installed-gallery validation. This does not block desktop widgets |
| Device and OS coverage | Connected-device workflows, Intel runtime behavior, older supported macOS versions and assistive interactions require separate checks |
| Runtime operations | Container image pinning/network policy and camera-file retention require an installation-specific operational decision; source publication does not change live containers or erase personal data |
| Ongoing review | New source/assets, dependency changes, security settings and each release artifact need their own review and accurate evidence record |

See the [current 0.1.2 verification record](release-verification-0.1.2.md), [0.1.1 history](release-verification-0.1.1.md), [source release preparation](source-release.md), [DMG packaging](../releases/dmg/README.md), [map lighting](map-lighting.md), [model regressions](model-regressions.md) and [security boundaries](../SECURITY.md).
