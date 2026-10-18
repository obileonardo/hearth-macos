# Documentation imagery

These images use the app's own views and illustrative device components with isolated, generated demo stores. No personal camera frames, household configuration, account details or owner recordings are included.

The showcase uses Hearth’s native illustrative components in six consistently sized panels: Climate, Security, Speakers, Energy, Assets and Rooms. This is a product overview composition, not six captured app windows. The previous generated showcase remains archived with its provenance; it is no longer the README hero.

Guide images use the source’s current `Theme.panelSize` viewport (448×696 points before outer export padding), with the same floating navigation overlay as the app. The connection guide supplies `homeassistant.local:8123`, the username `demo` and an empty password. Native text input, the Help version switch and the navigation-opacity slider and section switches are drawn statically for these offline illustrations, and the dock and heading close-ups use a solid documentation fallback. The running app uses adaptive translucent glass. This avoids unsupported-control placeholders in offscreen image rendering. The documentation environment is false by default: normal application text fields, switches, material and actions retain their native behavior.

The map uses the real SceneKit demo scene and the real map controls; its scene image is supplied to the layout renderer. Room names and devices are generated fixtures. View renderings are examples of the interface, not evidence of physical integration compatibility.

Regenerate with the developer `--render-preview` command using a new temporary output. Offline app initialization and exported activity use explicit memory-only logs with synthetic events; preview items cannot retain image or face references. Review every selected image and its metadata before copying it here. Keep recordings, camera photographs, operational logs and signing files private.

The navigation guide presents the real Settings navigation section in isolation within the shared demo frame. It is a section guide, not an additional screen in the app.

The Activity guide uses invented Front door, Garden and Driveway events. The empty Activity image contains no events and shows the actual viewport-based centering between its filter tray and floating dock. Header close-ups use illustrative cameras or system symbols, with 12-point panel insets, a 68-point card height and 26.25-point overlapping circles. No activity history or camera image is used.

## Source-guide refresh

The exporter also prepares `guide-rooms-overview-{dark,light}.png`, `guide-rooms-interactive-{dark,light}.png` and `guide-activity-empty-{dark,light}.png`. Rooms fixtures contain invented room names and speaker states; floor assignments are synthetic registry data. The interactive layout is a room browser, not a measured floor plan. The empty Activity guide has no stored event or image.

Export into a new temporary directory with a candidate build's `--render-preview` command. Review the actual pixels, dimensions and metadata before copying selected images here. Do not imply a new binary has shipped merely because source-guide images changed. Keep the published 0.1.3 release verification intact; source screenshots can show later candidate UI only when that distinction is stated.

The native illustration contact sheet can be reviewed with the same candidate executable's `--render-art <new-temporary-directory>` command. Calling the executable directly avoids `scripts/render-art.sh` rebuilding `Resources/AppIcon.icns`. The extra gadget/solar scale review sheets are review aids; they should not replace readable product guides in the README.

## Capture types in the current source guides

| Images | Method | Limitations |
|---|---|---|
| `guide-rooms-overview-*`, `guide-rooms-interactive-*` | Native AppKit host with the same scrolling viewport and shared app components | Offscreen window only; Menu and lazy room content render natively; no actual Home Assistant connection |
| `guide-activity-empty-*` | Native host with the live viewport-height, content-coordinate and dock-obstruction inputs | Geometry/state settles before capture; sample empty log only |
| `guide-connect-*` | Native host for the Settings page and its lower system switches | Server/username/password fields remain explicitly static documentation illustrations; generic address, `demo`, empty password |
| Other `guide-*` and product showcase | SwiftUI ImageRenderer, actual components and explicit documentation fallback controls/material | Native system glass composition and editable input behavior are not demonstrated by these images |
| `map-layout-{dark,light}.png` | The same SceneKit synthetic demo scene, camera and device placements inside the real map layout, captured offscreen in each appearance | Not an imported household scan, live system-glass recording or connected-device compatibility test |

The refreshed guide series contains light/dark views for Assets, speakers, climate, connection, Help, bug drafts, navigation, Activity, empty Activity, two Rooms layouts and three floating-heading variants. Page images preserve the app viewport; long content may continue behind the floating dock and can be scrolled in the running app. Header close-ups are isolated components, not full-page screenshots.

For this refresh, selected images were visually inspected and PNG metadata was checked for text and EXIF identity/time/location fields. Only dimensions, color-space and resolution tags were found. This review does not establish ownership of unknown earlier inputs or validate physical integrations. The archived generated raster showcase and app icon were not replaced by the guide refresh.

## 16 October 2026 source refresh

Generated with the 0.1.5 development candidate (build 20261016.2), separately from the installed app and the immutable 0.1.3 download. Room cards are 160-point squares in a 176-point horizontal viewport with 8-point vertical clearance; the strip reaches the panel edges. The climate guide now includes synthetic Auto/Dry/Fan modes, fan speeds and Swing/Sleep/Display companions, including the extra 2-point gaps. The console/controller and 144-half-cell solar library drawings were re-exported from the same source revision.

New `guide-account-*`, `guide-integrations-*` and `guide-integration-add-*` captures use the actual native Account and integration-manager views with explicit in-memory snapshots. The generic Demo User, homeassistant.local address, sample entries and HomeKit catalog are fixtures. Preview tasks return before account attachment, catalog requests, setup flows or avatar loading; brand-icon requests are disabled and the standard fallback symbol is shown. No Apple Home household, pairing PIN/QR, saved account or physical device is used. Controls in these screenshots are illustrative, not a recorded integration setup.

Room-card pixels, illustration scales and both integration screens were inspected after rendering. Actual mouse interaction is a separate verification step; a rendered image does not establish that dragging or physical controls work.

### Current climate guides

The two climate guides use the 0.1.5 build 20261016.7 candidate: the unit body is 15% larger, its natural layout begins 8 points lower and all following controls move with it. Cooling air becomes a fuller, pale mist toward the lower endpoint of the device’s validated temperature range. Wider moving lanes and a bounded visual pace change strengthen the wind without changing a real fan command. A continuous drawing clock keeps target changes fluid; Reduce Motion and power-off pause are retained. Heat, dry and fan-only keep their original appearance. The airflow receives a smooth alpha fade after its blurred layers are composited, including fractional backing pixels, so the plume disappears before the canvas edge.

Fixed-time 16°/24°/30° comparisons are developer review aids. The owner accepted size and spacing in the isolated review; the current mist balance is a subsequent refinement. Both appearances were inspected. No physical AC command was used to generate or review these images.


## Six-area showcase and map appearance refresh — 16 October 2026

Rendered from the focused branding source revision on `codex/brand-appearance-20261016`, based on the verified 0.1.6 source. `PreviewExporter` uses fresh isolated stores; the same SceneKit controller/camera supplies each map appearance. The actual `AppearanceSettings` control is rendered separately to explain **Settings → Appearance → Light, Dark or System**. The native icon comes from `AppIconArt` and the matching ICNS family uses all standard 16–1024 pixel sizes. See [identity notes](../art/brand-notes.md).

| Output | Dimensions | Content and verification |
|---|---|---|
| `../art/AppIcon-1024.png` | 1024×1024 | Native silver/blue mark on a navy tile; inspected at 1024, 128, 32 and 16 pixels; menu-bar glyph unchanged |
| `../art/hearth-native-showcase.png`, `../art/hearth-native-showcase-light.png` | 2104×1152 each | Six equal panels: Climate, Security, Speakers, Energy, Assets, Rooms. Actual project illustration components, aligned captions and synthetic temperature; both appearances visually inspected |
| `map-layout-dark.png`, `map-layout-light.png` | 2424×1584 each | Matching generated two-floor scene/camera/placements in the actual map layout. Both inspected; power is simulated |
| `guide-appearance-dark.png`, `guide-appearance-light.png` | 896×280 each | Actual shared Appearance setting, with System selected. Both inspected; no setting was changed through interaction |

All seven selected PNGs passed the metadata check: only dimensions, color-space and resolution EXIF tags, with no PNG text or identity/time/location metadata. Local OCR and face-region screening flagged none; this heuristic supplements visual review and does not guarantee detection of every private pixel. No owner screenshot, home scan, camera image, face, live account or recording was copied. Offscreen rendering does not establish live system-glass composition, universal contrast or physical integration support.

These source-guide changes are separate from the installed app and do not imply a new packaged release. The public download is the 0.1.8 release described in its [verification record](../release-verification-0.1.8.md).
