# Task update

Updated 15 October 2026. This register covers Claude's foundation, interrupted work completed by Codex, subsequent product feedback and publication. Implemented source, reviewed behavior and a downloadable release are recorded separately. Fixture checks do not establish compatibility with every physical device or supported Mac.

## Current work and delivery

The latest completed source batch is merged in private PR #11 and [public PR #6](https://github.com/obileonardo/hearth-macos/pull/6). Both hosted runs passed **129 XCTest cases, two GPU-dependent skips and zero failures**, plus release compilation, source-linked contrast, shell checks and optional universal WidgetKit compilation. The public [verification run](https://github.com/obileonardo/hearth-macos/actions/runs/38696784897) checks public app-source commit `e7fc0f61dc596cd70b37f4829e32a53613bb0711`, merged as `2161d69647d822a9153c0bdea5c786178e31b71d`. Private development history remains separate.

The downloadable release is still [0.1.2 preview](https://github.com/obileonardo/hearth-macos/releases/tag/v0.1.2-preview). The latest source changes below are **not in that DMG**. A further heading-card refinement and final 0.1.3 build, installation, verification and publication remain in progress.

| Work | Contribution | Current status and evidence | Remaining work |
|---|---|---|---|
| Native menu-bar app, sign-in and live state | Claude foundation; Codex review | Implemented; existing bundle identity and Keychain session preserved | Broader device/OS coverage below |
| Climate controls, timers, display, energy and modes | Claude foundation; Codex refinement | Capability-based controls retained; commands serialize per physical device, unsent temperature changes cancel before mode changes, and errors refresh authoritative state | Integration-specific limits remain |
| Intermittent AC mode rejection | Codex | One guarded retry for the specifically observed vendor rejection; fresh-state checks prevent retry after power/mode changes. Recovery fixtures passed; approved live mode checks accepted the requested modes and restored prior state | Intermittent vendor behavior is not declared permanently fixed; further physical reproduction may be needed |
| Temperature display and motion | Codex | Smooth local digit animation restored; modes without a setpoint show an em dash without an invented temperature slider | Included in source; final 0.1.3 DMG pending |
| Security, cameras, live video, activity and notifications | Claude foundation; Codex completion/polish | Existing camera streams, activity categories and preferences retained; unsupported hubs show honest availability | Vendor-specific camera features below |
| Rooms, floors, assets, gadgets, vehicles, homes and energy | Claude foundation; Codex completion | Implemented; saved-data regressions pass; Assets replaces only the overview display name, preserving saved routes and Home Assistant terminology | Real integrations require supported devices |
| Car model illustrations and remembered paint | Interrupted Claude work completed by Codex | Implemented; sample car/paint controls retained | Physical car integration coverage below |
| Live event pill and desktop widgets | Interrupted Claude work completed by Codex | Individual Overview links, movement, resizing and saved placement retained | Platform gallery provisioning is separate |
| Widget content and chosen climate source | Codex | Connected readings drive Overview, selected climate, recent Activity and Energy; documented in [widgets](../docs/widgets.md) | Additional real-device coverage |
| Native WidgetKit extension and shared snapshots | Codex | Source and optional universal compilation pass; unprovisioned extension omitted from preview | Host/extension provisioning, App Group and gallery activation |
| Cursor ownership | Codex | Arrow on controls and hand on the active map canvas; decorative dock lens does not receive pointer events; isolated cursor ownership checks pass | Broad native pointer-vibration feedback needs continued reproduction; not certified fully resolved |
| Device placement | Codex | Drag-out presentation, cancellation and last-placed-first ordering retained | No new dependency |
| AC airflow | Codex | More visible continuous animation; owner accepted appearance | No new dependency |
| Speaker presentation | Codex | Grid/list, connected glow, playback waves and grouping; actual grouping distinguished from the same track | No new dependency |
| Uniform asset cards and speaker text | Codex | Consistent tiles, room icons, centered hierarchy and wrapped names; owner accepted appearance | No new dependency |
| Device proportions | Codex | Larger fridge, TV and AC; Echo Dot reduced 30%; camera proportions refined | Further art direction remains optional |
| Native gadget illustrations | Codex | Console refined; solar panel rebuilt with a consistent 72-cell projection, slim frame, coherent supports and restrained daylight reflection; on/off and 24/46/72/160pt renders reviewed | Final 0.1.3 artifact pending |
| 3D map shadows and rendering | Codex | Contact shadows, improved masking and directional SceneKit lighting retained | Supported GPU/OS coverage below |
| Metal contact lighting | Codex | Native ray-traced contact pass with fallback; local M4 GPU checks passed | Not full path tracing; hosted GPU checks skip where unsupported |
| Map defaults, controls and toolbar | Codex | See-through collapsed map, consolidated full-map toolbar and smoother plan/3D transitions | No new dependency |
| Activity and page transitions | Codex | Unified six-option Activity filter tray without clipped side pills, filter transitions, text gradients, moving selection keys and scoped page motion refined; Reduce Motion retained | Broad animation smoothness requires native review |
| Assets → demo home → Back | Codex | Departing demo snapshots retained; native return to Assets reviewed; route fixtures pass | Latest heading refinement reviewed separately |
| Semantic navigation icons | Codex agent | Consistent semantic drawings and selected fills; Climate uses a snowflake; Reduce Motion respected | Further optical review remains possible |
| Floating bottom navigation | Codex | Full-height content scrolls behind the capsule; no full-width fade/black band; final controls remain reachable and fixed climate/demo controls clear the dock | Final 0.1.3 artifact pending |
| Navigation glass preference | Codex | Remembered 0–100% surface opacity, default 55%; foreground remains full opacity; Reduce Transparency/Increase Contrast force a solid surface. Native slider adjusted and restored during review | Final 0.1.3 artifact pending |
| Menu-bar pill and flash alerts | Codex | Owned status view avoids selection bezel; pill height increased where the menu bar permits; crisp flash edges reviewed and accepted by owner | Final 0.1.3 artifact pending |
| Stable open-panel position | Codex | Opening anchor retained through status updates; bounded status slot centers artwork; screen clamping and explicit reanchoring preserved; geometry fixtures pass | Native status-update review does not certify every display/menu-bar arrangement |
| Scrolled page heading | Codex | Translucent rounded heading card implemented with 16pt insets, overlapping camera/device illustrations and Activity/Settings category icons, smaller circles and an early original-title fade; native Security scroll/return reviewed | Complete hosted regression checks and source publication for this follow-up |
| Map and widget accessibility | Codex agents | Keyboard placement and named actions retained; Open full map has its own label/hint, confirmed through native accessibility inspection | Full VoiceOver review and additional machines below |
| Accessible blue and home energy palette | Codex | Rich adaptive blue, white marks on deeper blue and coherent green home-energy surfaces; source-linked normal/Increase Contrast checks pass | Live glass/photos still require visual review |
| Appearance and preference layouts | Codex agents | Immediate Light/Dark/System behavior, clearer widget/notification settings, right-aligned version switch and roomier integration controls | No new dependency |
| Help and support drafts | Codex | Local editable Subject/Message, preserved edits, optional versions off by default, Open mail app and Copy draft; contact@elvisobi.com; no automatic sending | User chooses when to send; actual mail-handler coverage varies |
| Speaker actions and capability routing | Codex agents | Registered capabilities and authoritative responses; idle supported Alexa devices request music on the chosen speaker; approved physical playback heard by owner and stopped | Announcement audibility can depend on DND/device behavior; separate confirmation remains |
| Credential and redirect boundaries | Codex | Home Assistant origin restrictions, redirect handling and session guards; regression checks pass | Ongoing security review, not a complete security certification |
| Home identity and map/scan compatibility | Codex | Unique scan imports and saved home/map compatibility retained; regressions pass | No new dependency |
| Public imagery and usage guides | Codex | Native showcase, coherent demo-only light/dark guides, explicitly memory-only synthetic activity, connection/use steps, artwork library and explicit static-control illustration provenance | Refresh images if the final heading follow-up changes visible views |
| Open-source preparation | Codex agents | License/notices, attribution, contributor/security guidance, issue/PR templates, generic examples and independently reviewed public history | Review every future export and release asset |
| Repository security and CI | Codex | Required PR/build checks, force-push/deletion protection, secret scanning/push protection, private security reports, dependency updates and pinned Actions | Keep protections active; latest batch evidence above |
| Universal build and DMG tooling | Codex agents | Apple Silicon/Intel builds, separate staging, provenance, signatures, read-only image/checksum validation and optional notarization workflow | Build and verify final 0.1.3 payload after source freeze |
| Published preview download | Codex | 0.1.2 ad-hoc preview available; fresh unauthenticated download matched its recorded checksum | Publish verified 0.1.3 DMG/checksum and update links; notarization input below |
| External-drive project relocation | Codex | Working files/history retained; original paths linked | External drive must remain connected |
| Task register and Claude handoff | Codex | Public status here; detailed operational handoff kept private | Update exact final artifact/source evidence after publication |

## Input, hardware and vendor requirements

These are distinct from the remaining 0.1.3 release work above. Existing features and saved data remain intact.

| Item | Needed to finish | Reason |
|---|---|---|
| Developer ID signed/notarized download | Local Developer ID Application certificate and notarization Keychain profile, then accepted submissions/stapling/Gatekeeper checks | Distribution credentials not installed/confirmed; ad-hoc preview is available |
| WidgetKit gallery | Matching host/extension provisioning, App Group and signing; installed-gallery validation | Platform provisioning; desktop widgets already work |
| HomePod / Apple TV | Local pairing and network permissions on supported hardware | Physical setup |
| Bambu printers | Actual model and supported cloud/LAN pairing | Physical/vendor setup |
| PlayStation / computer companion | Account pairing or companion setup | User setup |
| Inverter, battery/BMS and energy history | Exact models, protocol/logger and Home Assistant sensors | Hardware/vendor support |
| ConnectLife appliances | Supported local/cloud Home Assistant integration | Vendor setup not established |
| Cars, chargers and mowers | Supported devices and integrations | Fixtures do not establish physical compatibility |
| Smart-key / HomeKit routes | Product meaning and chosen integration | Owner decision |
| Advanced Eufy hub/face features and AC left/right functions | Exposed vendor/API capability and supported integration | Commands/data cannot be invented |
| Deferred router integration | Owner decision before enabling | Explicitly deferred |
| Camera retention and live container/network policy | Installation-specific operational decision | Personal history and working deployment preserved |
| Additional runtime/accessibility coverage | Older supported macOS, Intel hardware and full VoiceOver/manual checks | Current compile/fixture review does not cover every runtime |

## Verification history

The released [0.1.2 verification](../docs/release-verification-0.1.2.md) records 57 XCTest cases, two hosted GPU skips and zero failures, and its exact app source/checksum. [0.1.1 verification](../docs/release-verification-0.1.1.md) remains release history. Later source batches passed 107, then 110 cases before the current 129-case batch. Those source results do not change the existing DMG's provenance.

See [source/release status](../docs/open-source-readiness.md), [navigation](../docs/navigation.md), [widgets](../docs/widgets.md), [release policy](../docs/release-policy.md) and [map lighting](../docs/map-lighting.md). Private records, owner recordings, credentials and household runtime stores are excluded from public Git history.
