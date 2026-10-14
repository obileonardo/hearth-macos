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
| Semantic navigation icons | Codex agent | Complete; selected security, room and device glyphs fill blue and animate, respecting Reduce Motion |
| Menu-bar pill rendering and native panel anchoring | Codex | Complete in 0.1.2; owned status view avoids the native selection bezel, panel follows its menu-item anchor; current refinement and verification status is below |
| Map placement and widget accessibility actions | Codex agents | Complete; named actions and keyboard placement included; full VoiceOver review remains separate |
| Help and bug-report email drafts | Codex | Complete; contact@elvisobi.com, separate action/guidance cards, optional version fields off by default, no automatic sending |
| README illustration, artwork provenance and app screenshots | Codex | Complete; native showcase, consistent light/dark demo guides, explicit static setup-control illustrations and full artwork library |
| Adaptive blue brand and appearance preferences | Codex agents | Complete in 0.1.2; immediate Light/Dark/System switching and documented accessibility behavior |
| Settings, widget and notification preference layouts | Codex agents | Complete in 0.1.2; clearer grouping and a distinct preferences entry icon |
| Speaker capability routing and playback actions | Codex agents | Complete in 0.1.2; registered capabilities and authoritative Home Assistant responses used; approved local playback heard by owner |
| Credential-origin and redirect boundaries | Codex | Complete; regression checks pass |
| Home identity, scan import and saved map compatibility | Codex | Complete; regression checks pass |
| Source license, notices, contributor/security guidance and issue templates | Codex agent | Complete |
| Open-source publication | Codex agents | Complete; independent reviewed history at [hearth-macos](https://github.com/obileonardo/hearth-macos); private development history preserved |
| GitHub security and branch rules | Codex | Complete; secret scanning/push protection, private security reports, dependency updates, pinned Actions, PR/build requirements and force-push/deletion protection |
| Automated regression CI | Codex agents | Complete; [0.1.2 public run](https://github.com/obileonardo/hearth-macos/actions/runs/38549884465): 57 XCTest cases, zero failures, two hosted GPU skips; shell checks and optional universal WidgetKit compile pass |
| Universal app and DMG packaging | Codex agents | Complete; Apple Silicon/Intel payload and checksum verified |
| Public preview download | Codex | Complete; [0.1.2 preview](https://github.com/obileonardo/hearth-macos/releases/tag/v0.1.2-preview), explicitly not notarized; fresh unauthenticated download matched the recorded checksum |
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

See [0.1.2 release verification](../docs/release-verification-0.1.2.md), [0.1.1 verification history](../docs/release-verification-0.1.1.md), [widgets](../docs/widgets.md), [release policy](../docs/release-policy.md) and [map lighting](../docs/map-lighting.md). Private owner handoff files are deliberately excluded from public Git history.

## Released UI review — 14 October

The 0.1.2 preview includes the adaptive blue brand palette, immediate Light/Dark switching, native menu-panel anchoring, clearer Settings/widget/notification/Help layouts, filled selected navigation glyphs and immediate destination transitions. Speaker actions use registered capabilities and authoritative Home Assistant responses; idle Alexa devices start music on the chosen device. An approved physical playback check was confirmed by Home Assistant and heard by the owner. Announcements were accepted; audible delivery can depend on Do Not Disturb and device behavior. Unsupported camera hubs remain explicitly unavailable.

The expanded isolated suite contains 57 cases, including appearance, native-panel geometry and device-action routing. Private and public hosted checks passed with two GPU-dependent skips and no failures. The release verification record identifies the exact app-source commit and download checksum. No personal recordings, logs, device IDs or operational register files are included in the public tree.

## Current UI refinement — source implemented, delivery pending

The nine feedback items received at 11:01 on 14 October now have changes in the development source. They are not included in the published 0.1.2 preview. The next delivery still needs hosted CI, review of the actual installed build and native visual feedback. The current documentation images use isolated demo data.

| Feedback | Source change | Verification still needed |
|---|---|---|
| Cursor vibration | Decorative dock lens no longer receives events; cursor ownership and native panel guards refined | Reproduce and check on the owner's Mac; vibration is not claimed fully resolved |
| Pale blue on black | Richer adaptive blue with checked text contrast | Native light/dark review |
| Brown/orange home energy cards | Coherent green home and demo-energy accent | Native visual feedback |
| Help version-switch alignment | Switch stays at the far right within the card padding | Native layout review |
| Unhelpful Get help / Report a bug destination | Local editable Subject/Message draft, explicit Open mail app and Copy draft fallback; no automatic sending | Edit/copy/mail-handler checks on installed build |
| Text-heavy Settings | Shorter secondary text and clearer hierarchy, with controls preserved | Native layout review |
| Live-pill and account/integration spacing | Controls and headings regrouped; live-pill controls use their own settings page | Navigation and spacing review |
| Inconsistent navigation/preferences icons | Shared semantic drawings, uniform sizing and rounded strokes; selected fills and Reduce Motion retained | Native optical-size review |
| PlayStation illustration | Curved unequal plates, wider black core, stand and larger controller; on/off lighting and contact shadows retained | Native small/large artwork review |

## AC commands, temperature animation and pill refinements — source checked

Climate commands now run serially per device, cancel unsent temperature changes before a mode switch, and refresh authoritative state after failures. A scoped approved live check accepted Auto, Dry and Fan and restored the prior operating mode. No vendor-required delay or universal hardware compatibility is claimed. Temperature digits own their smooth local animation; modes without a setpoint no longer display an invented temperature. The climate guide images have been refreshed from isolated demo data.

The status capsule requests four extra points of height, safely bounded by the actual menu bar. Flash alerts retain crisp text and separate masked glass from shadows; the dismiss button has its own bounded hover region. Integrated build and final hosted checks, installation and publication are tracked separately.


## Latest owner feedback — 14 October, evening

| Feedback | Source work | Evidence / remaining review |
|---|---|---|
| Intermittent AC mode rejection remains | One guarded retry only for the observed vendor rejection, with fresh-state checks before resend; changed power/mode, unrelated errors and temperatures are never retried | Prior 95-case CI passed; new isolated recovery fixtures await this PR's final run. Direct vendor checks accepted all requested modes and restored prior power, but intermittent vendor behavior is not declared permanently fixed |
| Navigation feels crowded | Panel height+48, space above dock+32 and below+6; small-screen clamping retained | Local build passed; final native review pending |
| Selected lens hides icon colour | Native clear glass selection, with existing accessibility fallback | Local build passed; final native review pending |
| Dark pins/demo labels on blue | White symbols/text on a deeper blue solid fill, also used by blue demo controls | Source-linked contrast checks pass, including Increase Contrast |
| Power-button halo too large/busy | Smaller 60pt halo, lower opacity and shorter falloff | Demo render reviewed |
| Climate navigation illustration | Snowflake matches the documented Climate navigation icon | Demo render reviewed |

The installed 0.1.3 earlier preview is being updated to this final source after checks. Private PR #9 remains the first publication stage; public transfer, merge and refreshed download follow it. No public binary for this newest source has been published yet.
