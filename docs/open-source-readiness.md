# Open-source preparation status

Updated 2026-10-14. Source preparation, a public repository and a downloadable Mac release have separate completion gates.

## Implemented

| Area | Evidence |
|---|---|
| Source licensing | MIT license, upstream patch attribution, complete Apache/MIT notice files and artwork provenance |
| Contributor onboarding | README, contribution/security guidance, issue and PR templates, generic environment examples |
| Source hygiene | Reviewed tracked-file export; environment files, runtime data, recordings, private handoff and signing files excluded |
| Configuration | Compose uses generic `HEARTH_DATA` / `TZ` inputs; actual local configuration stays separate |
| Authentication boundaries | Artwork credentials restricted to the configured Home Assistant origin; cross-origin redirects strip authorization/cookies; embedded web-session injection has an origin guard |
| Data preservation | Scan imports choose unique filenames; primary-home edits retain its identity; packaging uses a separate staged app |
| Build automation | Hosted macOS release build, pinned official checkout action and read-only workflow token |
| GitHub security settings | Dependency alerts and security-fix PRs enabled; Actions limited to GitHub-owned and verified publishers; workflow approval permission remains disabled |
| Reporting | Settings support/bug-report drafts and a concrete private security contact at `contact@elvisobi.com` |
| Distribution tooling | Universal app build, separate DMG staging, version/provenance record, Developer ID signing, app/image notarization and SHA-256 output |

The authentication/data changes have source-review and compile evidence. Full adversarial, hardware and supported-OS coverage remains outstanding. No automated test suite was added or run during this preparation.

## History and publication

The current source tree uses generic configuration. Earlier private development history still includes installation-specific paths/settings and author identities whose public use has not been confirmed. A `.gitignore` change does not remove that history.

Prepare public source from a reviewed snapshot with independent history. Keep the private development repository and working installation intact. Review the exact exported files and assets before initializing/publishing the separate repository. Do not change the existing repository's visibility as a shortcut.

A heuristic review of the baseline main history found no identified credential literals; it does not prove that every possible encoded secret is absent. Binary assets need their own review, and artwork/trademark rights require owner decisions. Detailed private audit inventories stay outside public source.

## Remaining gates

| Gate | What is needed |
|---|---|
| Public repository | Owner approval of the reviewed snapshot, public name/ownership and publication destination |
| Artwork | Approval of recognizable product imagery, attribution and AI-assistance wording; Apple symbols retain Apple's applicable terms |
| Signed download | Developer ID Application certificate and a local notarization Keychain profile; accepted app/image submissions and stapled tickets |
| Repository rules | Required PR/build checks and protection against force pushes/deletion on the chosen repository; current private plan prevents configuring `main` protection |
| Private GitHub security reports | Availability/enabled state is unconfirmed on the private repository; email reporting is available |
| Release policy | Supported integrations/OS validation, version/release cadence, maintainers and privileged developer-tool policy |
| Runtime operations | Container image pinning/network policy and camera-file retention are separate decisions; preparation has not changed the working deployment or deleted personal data |

See [source release preparation](source-release.md), [DMG packaging](../releases/dmg/README.md) and [security boundaries](../SECURITY.md).
