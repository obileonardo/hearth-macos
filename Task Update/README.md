# Task update

Updated 14 October 2026. This register covers Claude's foundation, the interrupted work completed by Codex, subsequent product feedback and release work. “Complete” means implemented and reviewed; it does not imply every vendor device or supported macOS version was physically tested.

## Completed

| Work | Contribution | Status / evidence |
|---|---|---|
| Native menu-bar application, sign-in and live state | Claude foundation; Codex review | Complete; existing bundle identity and Keychain session preserved |
| Climate controls, timers, display, energy and modes | Claude | Complete; availability follows Home Assistant capabilities |
| Security, cameras, live video, activity and notifications | Claude foundation; Codex polish | Complete; unsupported vendor features remain unavailable |
| Rooms, floors, devices, gadgets, vehicles, homes and energy | Claude foundation; Codex completion | Complete; saved-data regressions pass |
| Car model illustrations and remembered paint | Interrupted Claude work completed by Codex | Complete; sample car/paint controls retained |
| Live event pill and desktop widgets | Interrupted Claude work completed by Codex | Complete; individual Overview links, movement, resizing and saved placement |
| Widget content choice and climate source | Codex | Complete; connected readings drive Overview, chosen climate device, recent Activity and Energy; documented in widgets.md |
| Native WidgetKit extension and shared snapshots | Codex | Code complete and universal compilation passed; gallery activation needs provisioning below |
| Arrow cursor on controls; hand on map canvas | Codex | Complete |
| Dragging devices out of cards; cancellation; last placed first | Codex | Complete; existing placement behavior retained |
| AC airflow visibility and continuous animation | Codex | Complete; user accepted visual result |
| Speaker grid/list, connected glow, playback waves and grouping | Codex | Complete; same track and actual grouping are distinguished |
| Uniform device tiles, room icons, centered layout and wrapped names | Codex | Complete; user accepted speaker appearance |
| Fridge, TV and AC proportions; Echo Dot reduction | Codex | Complete; Echo reduced by 30%; user accepted size |
| Outdoor camera proportions and native device models | Codex | Complete; latest camera likeness can receive further visual feedback |
| Contact shadows, masking and directional SceneKit lighting | Codex | Complete |
| Native Metal ray-traced contact lighting with fallback | Codex | Complete; local Apple M4 GPU checks passed; this is not full path tracing |
| See-through collapsed map and consolidated full-map toolbar | Codex | Complete |
| Moving selection pills, smoother map and page transitions | Codex | Complete; reduced-motion behavior preserved |
| Activity filter transition, text gradients and dock polish | Codex | Complete |
| Semantic navigation icons | Codex agent | Complete |
| Menu-bar pill rendering without the native selection bezel | Codex | Implemented; final appearance on the user's menu bar still welcomes visual confirmation |
| Map placement and widget accessibility actions | Codex agents | Complete; named actions and keyboard placement included; full VoiceOver review remains separate |
| Help and bug-report email drafts | Codex | Complete; contact@elvisobi.com, optional diagnostic fields, no automatic sending |
| README illustration, artwork provenance and app screenshots | Codex | Complete; sample-data screenshots and full library retained |
| Credential-origin and redirect boundaries | Codex | Complete; regression checks pass |
| Home identity, scan import and saved map compatibility | Codex | Complete; regression checks pass |
| Source license, notices, contributor/security guidance and issue templates | Codex agent | Complete |
| Open-source publication | Codex agents | Complete; independent reviewed history at [hearth-macos](https://github.com/obileonardo/hearth-macos); private development history preserved |
| GitHub security and branch rules | Codex | Complete; secret scanning/push protection, private security reports, dependency updates, pinned Actions, PR/build requirements and force-push/deletion protection |
| Automated regression CI | Codex agents | Complete; 36 XCTest cases, zero failures, two hosted GPU skips; shell and widget checks pass |
| Universal app and DMG packaging | Codex agents | Complete; Apple Silicon/Intel payload and checksum verified |
| Public preview download | Codex | Complete; [0.1.1 preview](https://github.com/obileonardo/hearth-macos/releases/tag/v0.1.1-preview), explicitly not notarized |
| Project relocation to external storage | Codex | Complete; working files/history retained, old paths linked; drive must remain connected |
| Task register and Claude handoff | Codex | Complete; detailed owner records stay private |

## Remaining input, hardware and vendor limits

| Item | Needed to finish | Why it remains |
|---|---|---|
| Developer ID signed and notarized download | Local Developer ID Application certificate and notarization Keychain profile | Credentials are not installed/confirmed; preview is available now |
| WidgetKit gallery registration | Valid host/extension provisioning, App Group and signing identity; native activation | Unprovisioned extension is omitted from the preview; desktop widgets work |
| HomePod / Apple TV | Local pairing and network permissions on supported devices | Physical setup required |
| Bambu printers | Actual model and supported cloud/LAN pairing | Physical/vendor setup required |
| PlayStation / computer companion | Account pairing or companion setup | User setup required |
| Inverter, lithium battery/BMS and energy history | Exact models, protocol/logger and Home Assistant sensors | Hardware/vendor support required |
| ConnectLife appliances | Supported local/cloud Home Assistant connection | Vendor setup not established |
| Cars, chargers and mowers | Supported physical devices and integrations | Fixture coverage does not establish real-device compatibility |
| Smart-key and HomeKit routes | Product meaning and chosen integration | User decision required |
| Eufy advanced hub/face features and AC left/right functions | Vendor/API capability and supported integration | Cannot invent unavailable commands/data |
| Deferred router integration | Owner decision before enabling it | Explicitly deferred |
| Camera retention and live container/network changes | Operational policy and deployment decision | Existing personal data and working deployment are preserved |
| Older supported macOS, Intel runtime and full VoiceOver coverage | Additional machines or manual review | Current compile/fixture checks do not cover all runtime combinations |
| Final pill/camera visual feedback | Review latest build on the user's Mac | Appearance is implemented; further art direction is optional |

See [release verification](../docs/release-verification-0.1.1.md), [widgets](../docs/widgets.md), [release policy](../docs/release-policy.md) and [map lighting](../docs/map-lighting.md). Private owner handoff files are deliberately excluded from public Git history.
