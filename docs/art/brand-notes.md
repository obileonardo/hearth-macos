# Hearth identity

The mark retains Hearth’s house-and-air silhouette: a roof, a quiet central point and three currents of air. The 16 October 2026 revision uses a silver roof and one rich blue material on a graphite/navy tile, with consistent upper-left lighting. Narrow reflections and shallow relief replace the earlier rainbow lighting, red rings and wide glow. Open spacing keeps the silhouette readable at small sizes.

`Sources/Hearth/Views/AppIcon.swift` defines the geometry and materials as SwiftUI Canvas code. `ArtExporter` generates `AppIcon-1024.png`; `scripts/render-art.sh` builds the matching macOS icon family. No reference photograph, external logo or generated bitmap is used in this revision. The existing monochrome menu-bar glyph is unchanged.

The README’s six-panel showcase uses the application’s native drawing components, rendered offline in both appearances. The Rooms building is an illustration of room/floor organization, not a measured scan. The actual map and guides use generated demo stores. See the [image register](../screenshots/README.md) for capture methods and [provenance register](../provenance-register.md) for licensing boundaries.
