# Home and map model regression checks

The XCTest target checks saved-data behavior using generated fixtures:

- Primary homes cannot be demoted, removed or assigned devices by an edit.
- Editing a secondary home cannot promote it to primary.
- Relinking a device keeps one assignment; linking to the main home unlinks it.
- Removing a secondary home returns its devices to the main home and keeps other homes intact.
- A manually named main home retains its name after Home Assistant location updates.
- Loading a list with no primary adds a fallback without discarding another home or rewriting the file.
- Explicit home files keep independent fixtures separate.
- Older map pins without floor information remain on the ground floor.
- Unknown device kinds retain their raw kind, identity and coordinates while using generic artwork.
- Saved pin positions, upper/basement floors, custom floor names and scan references round-trip unchanged.

`HomeList(file:)` injects a fixture location. Omitting the argument preserves the app's existing
Application Support location and `-homesFile` development override. Tests use unique temporary
directories, remove only their own fixtures, and never instantiate the shared home/map stores.

## Run with Xcode

```sh
source scripts/sdk.sh
swift test --filter 'HomePersistenceTests|MapModelCompatibilityTests'
```

The macOS Command Line Tools on the development Mac compile Hearth but do not include XCTest.
The full Xcode developer tools, as provided by the GitHub macOS runner, are required for the
actual XCTest target. Select the intended installed Xcode before running this command.

## Recorded local verification

On 14 October 2026, all 14 fixture cases passed against compiled Hearth model objects through
a temporary independent assertion runner, with zero assertion failures. That runner did not
call Hearth's application entry point or connect to Home Assistant. It was a local fallback
for the missing XCTest runtime; it was not XCTest discovery or a successful `swift test` run.

These model checks do not establish device-command behavior, gallery-widget provisioning,
Intel runtime behavior or operation on every supported macOS release. Those require separate
integration or hardware validation.
