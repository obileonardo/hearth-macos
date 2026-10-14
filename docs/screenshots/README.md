# Documentation imagery

These images use the app's own views and illustrative device components with isolated, generated demo stores. No personal camera frames, household configuration, account details or owner recordings are included.

The showcase is rendered from Hearth's native AC, camera, doorbell and speaker illustrations in consistently sized blue cards. The previous generated showcase remains archived with its provenance; it is no longer the README hero.

Guide images use a consistent 448×648 viewport. The connection guide supplies `homeassistant.local:8123`, the username `demo` and an empty password. Native text input and the Help version switch are drawn statically for these offline illustrations, and the dock uses an opaque material fallback. This avoids unsupported-control placeholders in offscreen image rendering. The documentation environment is false by default: normal application text fields, switches, material and actions retain their native behavior.

The map uses the real SceneKit demo scene and the real map controls; its scene image is supplied to the layout renderer. Room names and devices are generated fixtures. View renderings are examples of the interface, not evidence of physical integration compatibility.

Regenerate with the developer `--render-preview` command using a new temporary output and isolated initial activity folder. Review every selected image and its metadata before copying it here. Keep recordings, camera photographs, operational logs and signing files private.
