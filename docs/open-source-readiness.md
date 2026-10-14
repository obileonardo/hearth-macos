# Public source and release status

Updated 2026-10-14. [Hearth's public repository](https://github.com/obileonardo/hearth-macos) is available from a reviewed source snapshot with independent history. The private development repository, household data and working installation remain separate. The universal preview is ad-hoc signed; a notarized Mac release still requires distribution credentials.

## Completed

| Area | Evidence |
|---|---|
| Public source | Initial reviewed snapshot [`7f42c768`](https://github.com/obileonardo/hearth-macos/commit/7f42c768); no private development history transferred |
| Licensing and artwork | MIT license, third-party patch attribution, Apache/MIT notice files, artwork provenance and Claude/Codex assistance credits |
| Contributor onboarding | README, contribution/security guidance, issue and PR templates, generic environment examples and a release policy |
| Source hygiene | Reviewed export excludes credentials, runtime data, recordings, private handoff, signing profiles and generated builds; included screenshots use explicit sample data |
| Configuration | Compose uses generic `HEARTH_DATA` / `TZ` inputs; actual local configuration remains separate |
| Authentication boundaries | Artwork credentials stay at the configured Home Assistant origin; external redirects strip authorization/cookies; embedded web-session injection has an origin guard |
| Data preservation | Imports select unique scan filenames, primary-home edits preserve identity, fixture stores use explicit paths and packaging modifies a separate staged app |
| Hosted verification | [First public CI run](https://github.com/obileonardo/hearth-macos/actions/runs/38534020918) succeeded with 36 tests, 2 GPU-dependent skips and no failures; executable build, script checks and optional universal widget compile also passed |
| Repository protection | Active `main` ruleset requires pull requests and the hosted check, blocks force pushes/deletion; workflow token is read-only and checkout credentials are not persisted |
| Security reporting | Secret scanning, push protection and private vulnerability reporting enabled; support/security email is `contact@elvisobi.com` |
| Distribution tooling | Universal build, separate DMG staging, version/provenance manifest, strict signature/image/checksum verification, optional Developer ID app/image notarization and stapling |
| Preview download | [Universal 0.1.1 preview](https://github.com/obileonardo/hearth-macos/releases/tag/v0.1.1-preview) from `7f42c768`, verified and ad-hoc signed, not notarized. SHA-256: `9e60647485e725d91df4c216a3a81fab877330dc05f4fa21f76ec6028536873a` |
| Widgets and lighting | Interactive desktop widgets remain available; optional WidgetKit source and snapshot integration compile. Hybrid Metal contact lighting executed on an M4, with native SceneKit fallback |

The regression suite covers home/map compatibility, widget snapshots and geometry, origin/redirect boundaries and map-lighting guards. GPU-dependent tests skip on hosted runners without ray-tracing support. The local M4 geometry/kernel checks and hosted XCTest results are distinct evidence; neither establishes every Home Assistant device or supported OS combination.

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

See the [0.1.1 verification record](release-verification-0.1.1.md), [source release preparation](source-release.md), [DMG packaging](../releases/dmg/README.md), [map lighting](map-lighting.md), [model regressions](model-regressions.md) and [security boundaries](../SECURITY.md).
