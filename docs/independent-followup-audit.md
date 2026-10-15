# Independent follow-up audit

Recorded 15 October 2026. This is a source and read-only repository review following the 0.1.3 preview. It records the existing publication requirements; the supplied repeat master-audit prompt has since been reviewed, with private findings and authorized remediation. The source follow-up is tracked separately from the existing binary.

## Repository checks actually performed

| Area | Observed result | Evidence / boundary |
|---|---|---|
| Public access and reporting | Public repository, issues enabled, private vulnerability reporting enabled | Read-only GitHub repository and private-reporting APIs; sensitive reports use [Security](../SECURITY.md) |
| Main protection | Active `Protect main` ruleset; PR required; strict `macOS / Swift release build` check; force pushes and deletion blocked; no bypass actors | Ruleset `25063722`, including the check's GitHub Actions integration ID; zero mandatory approvals suits the present solo-maintainer workflow |
| Secret handling | Secret scanning and push protection enabled; zero open secret-scanning alerts returned | Read-only API at review time. No alert content was copied. Non-provider-pattern scanning and validity checks are not enabled; no settings were changed |
| Dependency review | Dependabot security updates enabled; zero open Dependabot alerts returned | Actions updates are configured weekly. This is not a vulnerability assessment of Home Assistant or vendor containers |
| Actions permissions | Selected publishers, GitHub-owned and verified actions allowed, SHA pinning required; default token read-only; workflow cannot approve PR reviews | Repository Actions permissions read-only APIs; checked-in workflow also uses `contents: read` and does not persist checkout credentials |
| Pull requests | No open public PRs at review time | A point-in-time observation; future implementation PRs are expected |
| Published preview | `v0.1.3-preview` remains a prerelease with universal DMG and checksum assets | GitHub release metadata; checksum digest matches the [0.1.3 verification record](release-verification-0.1.3.md). The previous record contains the actual unauthenticated download check |
| Source contribution path | README, contribution/security guidance, issue forms and PR template exist; public reports request redacted sample evidence | Checked-in files reviewed; developer commands' real-device access remains documented |
| Privacy boundaries | README and Security disclose local data, external artwork/icon requests, developer tools and unsandboxed preview status | Source reviewed in `ActivityLog`, `Faces`, `HAPictures`, `HAWebWindow`, `HAAdmin`, gadget reachability and widget snapshot storage |

These observations do not establish that a repository is free of secrets or vulnerabilities. Alert counts are dated observations, not a substitute for reviewing the exact source and release artifact.

## Work completed by this audit

| Finding | Resolution |
|---|---|
| Source-release guide described the old `macos-26` runner as current | Corrected to the checked-in `macos-15` / Xcode 26.3 workflow, included contrast verification, and separated 0.1.3 evidence from the historical first run |
| Remaining hardware and assistive checks were distributed across release notes | Added one [compatibility checklist](compatibility-checklist.md), with prerequisites, capability/readback requirements, restoration and clear unexecuted status |
| Retention and container/network decisions had no concrete review proposal | Added [retention and network options](retention-network-proposal.md), preserving current behavior and separating choices from implementation |

No repository protection was weakened. No credentials, camera images, household identifiers, local configuration, container state or personal history were read into these documents or changed by this audit.

## Follow-up ownership

| Can proceed independently | Requires input or a separate environment |
|---|---|
| Review accessibility labels/focus, cursor ownership and animation code; use isolated fixtures and demo views | Full VoiceOver use, Intel/older macOS runtime and GPU combinations need a suitable test environment |
| Fix documented or reproduced source defects; run the authorized regression/build checks; review future public exports | Live speaker/camera/alarm/vehicle actions need an agreed device, observable result and reversible test plan |
| Prepare packaging and provisioning instructions | Developer ID identity, notarization Keychain profile and WidgetKit provisioning remain local maintainer inputs |
| Inventory operational choices and design dry-run validation | Retention duration/deletion scope, backup destination, network exposure and maintenance window require installation-specific decisions |
| Maintain baseline repository documentation | The supplied master-audit criteria are being validated; future promotion copy is a separate editorial choice |

New implementation checks belong in their own change/release record. Do not rewrite 0.1.3's recorded binary provenance or describe this documentation audit as a new installed release.
