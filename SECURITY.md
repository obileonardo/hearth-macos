# Security

Hearth controls real devices through the Home Assistant session configured by its user. Treat its local data, session and developer tools as privileged access to that home.

## Reporting

Report security concerns privately to [contact@elvisobi.com](mailto:contact@elvisobi.com?subject=Hearth%20security%20report). Start with a brief description and affected version; arrange secure handling with the maintainer before sending sensitive material. Do not include credentials, camera images or household addresses. GitHub private vulnerability reporting may also be used when enabled.

Describe the affected commit, the reproduction steps using sample data, the expected result and the observed result. Never demonstrate a report against another person's home or devices.

## Current boundaries

- The refresh token is kept in macOS Keychain. The signed-in Home Assistant web view uses a nonpersistent data store and injects its session only at the configured Home Assistant origin.
- Home Assistant picture requests attach the bearer token only for the configured HTTP(S) origin, including its port. External artwork remains supported without that token. Cross-origin redirects strip authorization and cookies.
- Familiar-face matching runs locally. Saved camera pictures and face samples are personal data; display blur does not erase them.
- `--probe`, integration setup flags and environment overrides are currently available in release builds. They can use the user's existing session and must be treated as developer tools with real home access. Restricting these tools is a pending product decision.
- HTTP Home Assistant connections do not encrypt sign-in or session traffic. Use HTTPS outside a trusted local development connection.
- This app is not currently App Sandbox hardened or a notarized public binary release. Import only scans you trust. Source availability does not imply that binary distribution has been reviewed.
- The supplied Docker configuration includes LAN-accessible Home Assistant bindings and floating image tags. Development network isolation and image pinning need separate operational review before recreating any working containers.

## Before public release

Review the exact source and Git history being published, all screenshots and assets, GitHub security settings, dependency/container versions and distribution signing. Keep private installation files and transcripts outside the published source. A successful local build is not public-release security approval.
