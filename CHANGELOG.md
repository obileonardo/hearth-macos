# Changelog

## Unreleased

### Interface and interaction

- Add Settings → Help & Support with editable support/bug-report drafts to contact@elvisobi.com, a copy-address fallback, and optional version details.
- Replace the README contact sheet with a curated landscape device-family showcase while retaining the full illustration library.
- Integrate the menu-bar live pill and optional movable, resizable desktop widgets for climate, activity and home information, with one-click navigation and independent overview links.
- Add saved speaker grid/list views, connected-device illumination and sound-wave illustrations for playing speakers. Report Home Assistant group membership separately from matching track metadata.
- Improve AC airflow with continuous streams and travelling pulses while retaining mode colors, fan intensity, swing and reduced-motion behavior.
- Consolidate full-map controls into view options, keep floor selection accessible and move the demo notice out of the main toolbar.
- Limit the map grab cursor to the house canvas. Add a native device-card drag image, cancellation restoration and newest-placement ordering.
- Give large appliances clearer proportions on the map and add native 3D device models with an illustration fallback.
- Add recognizable electric-car illustrations and remembered paint choices without changing vehicle control behavior.
- Improve Devices grid sizing and shared selection animations.
- Add device-themed navigation glyphs, soften dock highlights, reserve content space above the dock and remove fading masks that obscured text.
- Replace Activity feed height folding with a short filter fade, retaining existing event categories, counts and settings.
- Smooth overview-to-detail and back navigation across devices, rooms, Settings and panel pages with scoped surface fades, short directional motion, and nonanimated layout swaps. Respect Reduce Motion and cancel stale navigation callbacks.
- Draw the menu-bar capsule in an owned status view to bypass the native button bezel, keeping the existing anchored panel and live status content.
- Match outdoor camera models to the sidebar illustration with an elongated round shell, lens face, rear mount and curved solar inset.
- Preserve the existing dock/settings layout, folding privacy-blur slider and full house rotation from the previously unpublished local commits.

### Home Assistant and data handling

- Add native floor creation and room-to-floor assignment, refreshing placement metadata without disconnecting live subscriptions.
- Restrict Home Assistant artwork/avatar authorization to the configured origin and remove authorization/cookies on cross-origin redirects.
- Guard embedded Home Assistant web-session injection by origin and validate integration-icon cache keys.
- Preserve existing scans when floor imports encounter filename collisions, and retain the main home's identity during edits.
- Apply privacy blur to camera imagery in the live pill and desktop widgets.

### Development and documentation

- Add universal Apple silicon/Intel builds and a separate DMG packaging workflow with preview labels, Developer ID signing, app/image notarization and checksums.
- Document a private security-reporting contact and keep distribution/signing outputs outside source control.
- Discover the installed SDK with an explicit override and a compatible Command Line Tools fallback.
- Add a release build option that leaves the installed app intact.
- Add isolated sample-data preview exports and separate activity/map development stores.
- Document storage and network behavior, contribution guidance, security boundaries and desktop-widget implementation limitations.

The app retains its macOS 14 deployment target and existing bundle identity. This branch does not change Home Assistant deployment, reset pairing, delete local data or provide a notarized binary release. Source builds and sample previews do not establish live hardware compatibility; public publication remains a separate reviewed step.
