# Preparing a source release

Hearth's [public repository](https://github.com/obileonardo/hearth-macos) was created from a reviewed source snapshot with independent history. Its first hosted build and regression run passed. This checklist describes how to prepare subsequent source and app releases while preserving the working installation. Preview downloads are ad-hoc signed; Developer ID signing and notarization remain separate distribution requirements.

## Preserve the working installation

Prepare the public tree in a separate directory. Keep the current repository, uncommitted changes, ignored files, installed app, Keychain session, UserDefaults, application support data, Home Assistant configuration and container volumes intact. Never clean private files from the installation to make a repository publishable. Do not change the app's existing bundle identifier as part of repository cleanup.

Use sample data for public screenshots. An export must exclude `.git`, `.claude`, `.build`, `build`, private transcripts and screen recordings, local `.env` files, Home Assistant runtime data, scans, camera pictures, face samples and account exports. Copy only reviewed source files; do not distribute a zip of the working directory.

## Release decisions

| Decision | Current policy |
|---|---|
| Public repository and history | Publish reviewed snapshots in `obileonardo/hearth-macos`; preserve the private development repository and its history. |
| Name and maintenance | Hearth is maintained by Elvis Obi under the [release and maintenance policy](release-policy.md); no fixed release schedule is promised. |
| Scope | Public source and clearly labeled preview downloads; a notarized Mac release additionally requires Developer ID credentials, accepted submissions and stapled tickets. |
| Artwork and attribution | Keep artwork provenance, third-party notices, applicable brand/symbol terms and the README's Claude/Codex assistance credits. Review new contributed material before redistribution. |
| Security contact | GitHub private vulnerability reporting is enabled; `contact@elvisobi.com` provides an email reporting channel. |
| Developer tools | Retain the documented CLI features. They act only when explicitly invoked and may use the user's Home Assistant session. |
| Compatibility | Target macOS 14 or later; record actual OS/integration checks and unverified combinations with every release. |

## Review the exact candidate

1. Record the candidate commit, tree, included refs and intended public repository. Review the actual files and the entire reachable history being transferred, including commit metadata and assets.
2. Check secrets and personal data, dependency and container versions, authentication boundaries, developer command privileges, imported file behavior and distribution signing. Resolve confirmed blockers; a build alone does not establish publication readiness.
3. Compile with Xcode 26 or a compatible macOS 26 SDK. The deployment target is macOS 14; the source uses macOS 26 APIs behind availability guards. A compile on one runner does not prove all supported runtime versions work.
4. Review sample screens and core device workflows. Record hardware or OS combinations that have not been checked. Use an isolated development server for commands.
5. Review MIT and third-party attribution. Ensure notices accompany any third-party material actually redistributed.
6. Review documentation links, clean-clone instructions, screenshots and examples against that candidate's source, rather than unpublished local changes.
7. Publish the reviewed candidate according to the release policy, with accurate signing/test status and recorded authorization. Preserve private history and the working installation.

## GitHub configuration

As of 14 October 2026, the public repository has secret scanning, push protection, private vulnerability reporting and an active `main` ruleset requiring pull requests and the hosted build check while blocking force pushes and deletion. The workflow token is read-only and checkout credentials are not persisted. Keep these controls under review:

- Private vulnerability reporting and a monitored response process.
- Secret scanning and push protection; review any existing alerts.
- Dependabot alerts and updates. The supplied configuration updates GitHub Actions pins.
- A rule for `main` requiring pull requests and the `macOS / Swift release build` check, preventing force pushes and deletion. Add review requirements appropriate to the maintainer count.
- Actions restricted to approved publishers; least-privilege default token permissions. Fork PRs must not receive credentials or run on the household Mac.
- Maintainer two-factor authentication and a review of collaborators/deploy keys.

The current workflow uses a fresh GitHub-hosted `macos-15` runner with Xcode 26.3 and a pinned checkout action. It builds the executable, runs isolated XCTest regressions, verifies source-linked appearance contrast, checks shell syntax and compiles the optional universal WidgetKit extension. The [0.1.3 public run](https://github.com/obileonardo/hearth-macos/actions/runs/38703085752) passed 137 tests, with 2 GPU-dependent skips and no failures. The [first public run](https://github.com/obileonardo/hearth-macos/actions/runs/38534020918), retained as historical evidence, passed 36 tests with 2 GPU-dependent skips and no failures. It does not launch or install Hearth, contact a home, use Developer ID/notarization credentials or publish app assets. Fixture and optional GPU checks do not establish connected-device or every-supported-OS compatibility. GitHub documents [hosted runners](https://docs.github.com/en/actions/reference/runners/github-hosted-runners) and [repository rules](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/about-rulesets).

## Release record

For an approved candidate, write a release note with the exact commit, supported OS/Home Assistant versions, changes, checks actually performed and known limitations. Keep detailed private installation inventories and sensitive security findings outside the public tree. A future binary release additionally needs reviewed hardened-runtime entitlements, Developer ID signing, notarization and a distribution validation record.
