# Contributing to Hearth

Hearth is a native SwiftUI macOS app built with Swift Package Manager. It uses system frameworks and has no third-party Swift package dependencies.

Building requires Xcode 26 or compatible Command Line Tools with a macOS 26 SDK. The app's runtime deployment target remains macOS 14. Use [SECURITY.md](SECURITY.md) for sensitive reports, rather than a public issue.

1. Read the README and the documentation for the feature you are changing.
2. Follow [local development](docs/local-development.md), then run `scripts/build.sh --debug`. It creates `build/Hearth.app` without installing it. The optional Home Assistant dev container is not automatically seeded; fixtures require the documented setup.
3. Review sample screens with `build/Hearth.app/Contents/MacOS/Hearth --render-preview /tmp/hearth-previews -activityFolder /tmp/hearth-preview-activity`.
4. Run `swift test` with full Xcode selected. The fixture tests isolate saved-data, widget, origin-boundary and map-lighting behavior; the current Command Line Tools setup alone lacks XCTest. See [model regressions](docs/model-regressions.md).
5. Describe the change, the checks you performed and anything you could not check.

Set `HEARTH_SDKROOT` if you need a particular installed SDK. The current Command Line Tools setup uses the macOS 26.5 SDK for SwiftUI macros; full Xcode may use its default SDK.

Use sample data and an isolated Home Assistant for device behaviour. The developer CLI can issue real commands using the app's Keychain session. Never paste credentials or personal device details into an issue, screenshot or commit. Keep development stores separate with `-homesFile`, `-gadgetsFile`, `-facesFolder` and `-activityFolder`.

Preserve existing controls, integrations, bundle identifier and saved data compatibility. Reuse `Theme`, `Bezel` and the shared control styles. Check light and dark appearance, long labels, offline devices and macOS accessibility settings. Every new camera image surface must use the existing privacy blur.

Build scripts install release builds by default. Use `--no-install` when reviewing a release build. Never restart or reconfigure somebody's working Home Assistant as part of a code cleanup.

The [provenance register](docs/provenance-register.md) records source and asset attribution, with unresolved evidence explicitly identified. Do not infer ownership from a Git author or an AI tool output. The illustrations are drawn in SwiftUI Canvas. Changes to their proportions should be reviewed at both card and contact-sheet sizes. Friendly device labels in `EntityCatalog.swift` are a useful starting point for contributions.

Submit original contributions under the project's MIT license. Include attribution and the original license for any third-party material; see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md). Describe substantial AI assistance in your pull request and review generated changes before submission. Contributor guidance does not require a separate copyright assignment.

The build workflow uses a hosted macOS runner with read-only repository permissions. It builds the executable, runs isolated XCTest regressions, checks shell syntax and compiles the optional universal widget extension. GPU-dependent cases skip when the runner lacks ray-tracing support. It does not launch or install Hearth, connect to a home, use distribution-signing credentials or publish a binary. A passing build and fixture suite do not establish physical-device compatibility.
