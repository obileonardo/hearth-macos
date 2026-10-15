# Documentation imagery

These images use the app's own views and illustrative device components with isolated, generated demo stores. No personal camera frames, household configuration, account details or owner recordings are included.

The showcase is rendered from Hearth's native AC, camera, doorbell and speaker illustrations in consistently sized blue cards. The previous generated showcase remains archived with its provenance; it is no longer the README hero.

Guide images use a consistent 448×696 viewport, with the same floating navigation overlay as the app. The connection guide supplies `homeassistant.local:8123`, the username `demo` and an empty password. Native text input, the Help version switch and the navigation-opacity slider and section switches are drawn statically for these offline illustrations, and the dock and heading close-ups use a solid documentation fallback. The running app uses adaptive translucent glass. This avoids unsupported-control placeholders in offscreen image rendering. The documentation environment is false by default: normal application text fields, switches, material and actions retain their native behavior.

The map uses the real SceneKit demo scene and the real map controls; its scene image is supplied to the layout renderer. Room names and devices are generated fixtures. View renderings are examples of the interface, not evidence of physical integration compatibility.

Regenerate with the developer `--render-preview` command using a new temporary output. Offline app initialization and exported activity use explicit memory-only logs with synthetic events; preview items cannot retain image or face references. Review every selected image and its metadata before copying it here. Keep recordings, camera photographs, operational logs and signing files private.

The navigation guide presents the real Settings navigation section in isolation within the shared demo frame. It is a section guide, not an additional screen in the app.

The Activity guide uses invented Front door, Garden and Driveway events. Header close-ups use illustrative cameras or system symbols, with 16-point panel insets and smaller overlapping circles. No activity history or camera image is used.
