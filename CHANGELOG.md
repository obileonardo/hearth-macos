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
- Add device-themed navigation glyphs, soften dock highlights, reserve content space above the dock and keep text clear as it scrolls.
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

## 0.1.3 preview candidate

- Richer blue accents, green home energy surfaces, consistent navigation glyphs and clearer Settings spacing.
- Local editable help and bug-report drafts with preserved edits, optional version details and mail/copy actions.
- Scoped map cursor ownership prevents hidden or overlapping scenes from changing the pointer.
- Per-device climate command sequencing, authoritative refresh after errors, and cancellation of unsent temperature requests before mode changes.
- Add one state-checked retry for the specifically observed intermittent vendor mode rejection; persistent failures remain visible.
- Add 48 points of panel height with 32 points more space above navigation and 6 below; use clear native selection glass, white-on-deeper-blue map marks and a gentler power halo.
- Use a snowflake for Climate navigation.
- Add remembered navigation glass opacity, with solid accessibility overrides; keep icons fully visible and refine the selected lens motion.
- Float the scrolled page heading in a compact translucent rounded card with 16-point top/side spacing, overlapping native device illustrations, Activity/Settings symbols and an early title fade; rename the overview to Assets while preserving saved routes.
- Keep the open panel stable during rotating menu status, with a bounded centered status slot.
- Refine the native solar-panel cell grid, metal frame, supports and daylight reflection.
- Float navigation over the full-height scrolling viewport, with no full-width fade or blur band. Extra trailing scroll space keeps final controls reachable; fixed climate controls and the demo exit stay clear of the dock.
- Give the full-map button its own VoiceOver label and hint.
- Restore the animated temperature digits; modes without a setpoint show an em dash and no temperature slider.
- Add four points of menu-pill height where the menu bar allows, and remove whole-notification blur and scaling from flash alerts.
- Refine the game-console illustration and refresh demo-only documentation guides.
- Use a full-panel scroll viewport without an inner top/side cutout and a compact six-option Activity filter tray.
- Make offline activity previews explicitly memory-only from app initialization, with synthetic events and no image/face references.
- Add isolated regression coverage for cursor ownership, support drafts, climate commands, queue behavior and pill geometry, plus a source-linked contrast check in CI.

## 0.1.2 preview

- Adaptive blue accents, reliable appearance switching and cleaner Settings, widget, notification and Help layouts.
- Native anchored menu panel with screen-aware bounds, outside-click/Escape dismissal and coalesced status refresh.
- Immediate page transitions retain departing scene state; selected semantic navigation glyphs fill and animate.
- Capability-aware speaker playback and music selection, acknowledged announcements, visible errors and authoritative device state.
- Explicit unsupported-hub camera messaging; no false-success toggles.
- Native illustration showcase, consistently framed demo views and illustrated connection/usage guides.
- Isolated appearance, menu geometry and action regressions extend the suite to 57 tests.
