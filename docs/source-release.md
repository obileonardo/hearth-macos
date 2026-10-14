# Preparing a source release

This is a publication checklist, not approval to publish. A source release and a downloadable Mac app are separate deliverables.

## Preserve the working installation

Prepare the public tree in a separate directory. Keep the current repository, uncommitted changes, ignored files, installed app, Keychain session, UserDefaults, application support data, Home Assistant configuration and container volumes intact. Never clean private files from the installation to make a repository publishable. Do not change the app's existing bundle identifier as part of repository cleanup.

Use sample data for public screenshots. An export must exclude `.git`, `.claude`, `.build`, `build`, private transcripts and screen recordings, local `.env` files, Home Assistant runtime data, scans, camera pictures, face samples and account exports. Copy only reviewed source files; do not distribute a zip of the working directory.

## Owner decisions

| Decision | Preparation recommendation |
|---|---|
| Public repository and history | Choose whether to retain reviewed history or publish a reviewed source snapshot to a separate repository. Do not rewrite the working repository. |
| Name and ownership | Confirm the public project name, copyright ownership and rights to submitted code/art. |
| Scope | Choose source-only first release or a separately signed and notarized binary release. The existing build script is for local development installation. |
| Product artwork and attribution | Review recognizable product illustrations and third-party notices, and choose the public AI-assistance credit wording. |
| Security contact | Enable private vulnerability reporting or provide a monitored private contact before inviting sensitive reports. |
| Developer tools | Decide whether release builds should retain privileged command-line Home Assistant operations. |
| Maintenance | Choose maintainers, supported versions and a release cadence. |

## Review the exact candidate

1. Record the candidate commit, tree, included refs and intended public repository. Review the actual files and the entire reachable history being transferred, including commit metadata and assets.
2. Check secrets and personal data, dependency and container versions, authentication boundaries, developer command privileges, imported file behavior and distribution signing. Resolve confirmed blockers; a build alone does not establish publication readiness.
3. Compile with Xcode 26 or a compatible macOS 26 SDK. The deployment target is macOS 14; the source uses macOS 26 APIs behind availability guards. A compile on one runner does not prove all supported runtime versions work.
4. Review sample screens and core device workflows. Record hardware or OS combinations that have not been checked. Use an isolated development server for commands.
5. Review MIT and third-party attribution. Ensure notices accompany any third-party material actually redistributed.
6. Review documentation links, clean-clone instructions, screenshots and examples against that candidate's source, rather than unpublished local changes.
7. Obtain the owner's final approval of the concrete candidate before changing visibility, publishing release assets or replacing history.

## GitHub configuration

Configure these on the chosen repository when available for its plan and visibility:

- Private vulnerability reporting and a monitored response process.
- Secret scanning and push protection; review any existing alerts.
- Dependabot alerts and updates. The supplied configuration updates GitHub Actions pins.
- A rule for `main` requiring pull requests and the `macOS / Swift release build` check, preventing force pushes and deletion. Add review requirements appropriate to the maintainer count.
- Actions restricted to approved publishers; least-privilege default token permissions. Fork PRs must not receive credentials or run on the household Mac.
- Maintainer two-factor authentication and a review of collaborators/deploy keys.

The build workflow uses a fresh GitHub-hosted `macos-26` runner, a pinned checkout action and a read-only token. It compiles without launching Hearth or contacting a home. It does not sign, notarize, upload an app, install it or run hardware tests. Verify its first completed run before treating it as a required status check. GitHub documents [hosted runners](https://docs.github.com/en/actions/reference/runners/github-hosted-runners) and [repository rules](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/about-rulesets).

## Release record

For an approved candidate, write a release note with the exact commit, supported OS/Home Assistant versions, changes, checks actually performed and known limitations. Keep detailed private installation inventories and sensitive security findings outside the public tree. A future binary release additionally needs reviewed hardened-runtime entitlements, Developer ID signing, notarization and a distribution validation record.
