# Documentation imagery

These images use the app's own views and illustrative device components with isolated, generated demo stores. No personal camera frames, household configuration, account details or owner recordings are included.

The showcase is rendered from Hearth's native AC, camera, doorbell and speaker illustrations in consistently sized blue cards. The previous generated showcase remains archived with its provenance; it is no longer the README hero.

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
| `map-layout-dark.png` | SceneKit synthetic demo image inside the real map layout, captured offscreen | Not an imported household scan or a connected-device compatibility test |

The refreshed guide series contains light/dark views for Assets, speakers, climate, connection, Help, bug drafts, navigation, Activity, empty Activity, two Rooms layouts and three floating-heading variants. Page images preserve the app viewport; long content may continue behind the floating dock and can be scrolled in the running app. Header close-ups are isolated components, not full-page screenshots.

For this refresh, selected images were visually inspected and PNG metadata was checked for text and EXIF identity/time/location fields. Only dimensions, color-space and resolution tags were found. This review does not establish ownership of unknown earlier inputs or validate physical integrations. The archived generated raster showcase and app icon were not replaced by the guide refresh.
