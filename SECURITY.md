# Security

Hearth controls real devices through the Home Assistant session configured by its user. Treat its local data, session and developer tools as privileged access to that home.

## Reporting

Report security concerns through [GitHub private vulnerability reporting](https://github.com/obileonardo/hearth-macos/security/advisories/new), which is enabled, or privately to [contact@elvisobi.com](mailto:contact@elvisobi.com?subject=Hearth%20security%20report). Start with a brief description and affected version; arrange secure handling with the maintainer before sending sensitive material. Do not include credentials, camera images or household addresses.

Describe the affected commit, the reproduction steps using sample data, the expected result and the observed result. Never demonstrate a report against another person's home or devices.

## Current boundaries

- The refresh token is kept in macOS Keychain. The signed-in Home Assistant web view uses a nonpersistent data store and injects its session only at the configured Home Assistant origin.
- Home Assistant picture requests attach the bearer token only for the configured HTTP(S) origin, including its port. External artwork remains supported without that token. Cross-origin redirects strip authorization and cookies.
- Familiar-face matching runs locally. Saved camera pictures and face samples are personal data; display blur does not erase them.
- `--probe`, integration setup flags and environment overrides remain available in release builds under the [release policy](docs/release-policy.md). They act only when explicitly invoked, can use the user's existing session and must be treated as developer tools with real home access.
- HTTP Home Assistant connections do not encrypt sign-in or session traffic. Use HTTPS outside a trusted local development connection.
- The main app is not App Sandbox enabled. Release downloads from 0.1.8 onward are Developer ID signed with hardened runtime and notarized by Apple; the earlier 0.1.1–0.1.3 previews were ad-hoc signed and not notarized. The optional WidgetKit extension has separate sandbox/provisioning requirements. Import only scans you trust.
- The supplied Docker configuration includes LAN-accessible Home Assistant bindings and floating image tags. Development network isolation and image pinning need separate operational review before recreating any working containers.

## Release review

The public repository uses a reviewed source snapshot with independent history. Secret scanning, push protection and private vulnerability reporting are enabled, and `main` has pull-request/build protection against force pushes and deletion. For each release, review the exact source, screenshots/assets, dependency/container versions and distribution signing. Keep private installation files and transcripts outside public source. Fixture tests and source review do not establish complete adversarial or physical-device coverage.
