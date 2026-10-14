# Hearth disk images

## Download

[Download Hearth 0.1.2 preview for Apple Silicon and Intel](https://github.com/obileonardo/hearth-macos/releases/download/v0.1.2-preview/Hearth-0.1.2-universal-PREVIEW.dmg) · [SHA-256 file](https://github.com/obileonardo/hearth-macos/releases/download/v0.1.2-preview/Hearth-0.1.2-universal-PREVIEW.dmg.sha256) · [release notes](https://github.com/obileonardo/hearth-macos/releases/tag/v0.1.2-preview).

This preview is ad-hoc signed and **not notarized**. macOS may block a downloaded copy. The Developer ID signed and notarized download awaits local signing credentials. See the [0.1.2 verification record](../../docs/release-verification-0.1.2.md); the [0.1.1 record](../../docs/release-verification-0.1.1.md) is retained as release history.

The published 0.1.2 image's SHA-256 is `8b100910bdc7ec4a352bce41843be2376f5173ca279db10487b117d0f2b2b7b1`. A fresh unauthenticated GitHub download matched this checksum. Its `BuildInfo.txt` records reviewed public app-source commit `accbedca5492976cffe098b4ec27707849b95296`; later documentation commits do not change that binary's provenance.

Generated `.dmg` and `.sha256` files go here and are ignored by Git. The packaging script does not install, quit or launch Hearth, or change Home Assistant, account credentials, homes, history or preferences. It builds and signs a separate staged app.

## Local preview

```sh
scripts/package-dmg.sh --version 0.1.2 --preview
```

This builds an optimized universal app for Apple silicon and Intel, then creates `Hearth-0.1.2-universal-PREVIEW.dmg`. It is ad-hoc signed and **not notarized**; macOS may block a downloaded copy. The versioned public preview is available above; a completed notarized release still requires signing setup.

To package an existing universal app without rebuilding:

```sh
scripts/package-dmg.sh --version 0.1.2 --preview --skip-build
```

`--app /path/to/Hearth.app` selects another existing app. Packaging only changes its staged copy. Both architectures are required. For release distribution, supply an optimized release build rather than a debug app.

## Signed and notarized release

Obtain a **Developer ID Application** certificate and create a local `notarytool` Keychain credential profile. Keep certificates, private keys and passwords outside this repository. An Apple Development certificate is for development and does not qualify here.

```sh
HEARTH_BUILD_NUMBER=1 scripts/package-dmg.sh \
  --version 0.1.2 \
  --identity 'Developer ID Application: YOUR NAME (TEAMID)' \
  --notary-profile hearth-release
```

The script enables hardened runtime, obtains a secure timestamp, submits the staged app and disk image to Apple, checks both for `Accepted`, staples and validates both tickets, and assesses both with Gatekeeper. The copied app carries its own ticket after the disk image is ejected. It writes the final `Hearth-0.1.2-universal.dmg` only after those steps succeed. This command uses the network and may wait several minutes. It reads an existing credential profile; it does not create one or accept passwords as arguments.

An identity without `--notary-profile` creates a clearly named `signed-unnotarized` image. It is an intermediate artifact, not a completed notarized release. Existing output files are never overwritten.

## Contents and checksums

The script uses `diskutil image create from` on newer macOS versions and falls back to
`hdiutil create` on older systems. It verifies the disk image's embedded checksums before
releasing the artifact. A legacy `hdiutil` HFS+ creation attempt stalled on the development
Mac; the current DiskImages2 folder path was verified with a separate temporary payload.

Each image contains only:

- `Hearth.app`, with its executable, app icon and bundle metadata.
- An `Applications` shortcut.
- Installation instructions.
- `BuildInfo.txt`, recording source commit, whether the working tree was modified, architecture and signing mode.

No source files, configuration, transcripts, camera images or personal settings are included. Debug symbols are removed from the staged executable. New app resources require review of the packaging allowlist rather than being silently omitted or copied.

`HEARTH_SOURCE_COMMIT` can identify the exact reviewed commit when packaging a supplied app; set it only when its provenance is known. Without this override, the manifest records the checkout commit and working-tree state. The script is reproducible as a workflow, not byte-for-byte: code-signing timestamps and disk-image metadata change between runs.

Before uploading, review the manifest and retain the checksum alongside the image:

```sh
cd releases/dmg
shasum -a 256 -c Hearth-0.1.2-universal-PREVIEW.dmg.sha256
```

Upload the completed image and checksum as assets on the matching GitHub Release. This script does not upload or publish anything. GitHub release assets are the download links; committing a DMG to the source repository is unnecessary.

See Apple's [notarization requirements](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution) and [Developer ID guidance](https://developer.apple.com/developer-id/).
