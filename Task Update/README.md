# Task update

Updated 16 October 2026. This register covers Claude's foundation, interrupted work completed by Codex, subsequent product feedback and publication. Implemented source, reviewed behavior and a downloadable release are recorded separately. Fixture checks do not establish compatibility with every physical device or supported Mac.

## Current source follow-up

The follow-up source includes the queued illustration refinements, 12-point floating-header insets with 25% smaller trailing circles, an optional interactive Rooms browser, contextual Climate/event icons and centered empty states. It also includes origin-bound sessions, safe Keychain persistence, embedded-web sign-out invalidation, exact-target command reconciliation, check-only maintenance patches, preserved binary notices and safer installation tooling.

The repeated open-source audit has been performed; its sensitive findings and operational handoff stay private. Architecture, setup, usage, provenance and container guides are included, with 41 refreshed synthetic PNGs. All 92 documentation PNGs were checked for identifying metadata. The rights holder confirmed authority for original code and illustrations; documented third-party terms still apply.

These source changes are distinct from the released 0.1.3 download below. The first combined private hosted check passed 220 XCTest cases with two GPU skips and no failures, plus 27 release/maintenance fixtures and the build/contrast/shell/optional WidgetKit gates. Additional regressions cover empty-room pages and malformed temperature, power, duration and battery readings; each final source revision must pass the required hosted check. Source preparation does not update an installed app or publish a new download. Final public-candidate checks and publication approval remain delivery gates.

### Current illustration and Rooms pass — 16 October

A further source revision responds to the latest visual feedback: the console now has a near-front Slim-style silhouette, four curved covers, a recessed front and distinct disc-drive shoulder, with a revised controller. The solar illustration uses a regular 144-half-cell layout, one projected frame and evenly spaced supports. The interactive Rooms strip uses square cards and adds mouse-drag browsing alongside native scrolling. These are prepared source changes; combined build, final art renders and native interaction review for this revision remain pending. Earlier image counts and completed checks above describe the preceding source revision. No new installed app or download is claimed here. Visual references and their limits are recorded in [provenance](../docs/provenance-register.md#console-and-solar-visual-reference-pass--16-october-2026).

## Released 0.1.3 baseline

The final 0.1.3 app-source batch is merged in private PR #12 and [public PR #7](https://github.com/obileonardo/hearth-macos/pull/7). Both hosted runs passed **137 XCTest cases, two GPU-dependent skips and zero failures**, plus release compilation, source-linked contrast, shell checks and optional universal WidgetKit compilation. The public [verification run](https://github.com/obileonardo/hearth-macos/actions/runs/38703085752) checks app-source commit `1d13b39c3c42711b67dde66c67bb0c21e290f10a`, merged as `4444e00a58de912e0b398e10a320f9b107de5b41`. Private run `38701418337` checks `d1b4f88700f9b97ac445e023437b5d18acd5603f`, merged as `0f61b852be29acd419a17180f018954d376d1f56`, before public transfer. Private development history remains separate.

The [0.1.3 universal preview](https://github.com/obileonardo/hearth-macos/releases/tag/v0.1.3-preview) is version 0.1.3, build `20261015.5`, with SHA-256 `9c0b1608d4d49557a1cbe963562d83d00bf9dafaf528a03aef3f034641c2e78a`. It is ad-hoc signed and **not notarized**. A fresh unauthenticated download matched both the packaged SHA-256 and published checksum. See the [0.1.3 verification record](../docs/release-verification-0.1.3.md) for the exact source, artifact and review evidence. This records the completed 0.1.3 batch. The source follow-up above is a separate delivery; setup, hardware, vendor and broader manual-coverage requirements remain below.

| Work | Contribution | Current status and evidence | Remaining work |
|---|---|---|---|
| Native menu-bar app, sign-in and live state | Claude foundation; Codex review | Implemented; existing bundle identity and Keychain session preserved | Broader device/OS coverage below |
| Climate controls, timers, display, energy and modes | Claude foundation; Codex refinement | Capability-based controls retained; commands serialize per physical device, unsent temperature changes cancel before mode changes, and errors refresh authoritative state | Integration-specific limits remain |
| Intermittent AC mode rejection | Codex | One guarded retry for the specifically observed vendor rejection; fresh-state checks prevent retry after power/mode changes. Recovery fixtures passed; approved live mode checks accepted the requested modes and restored prior state | Intermittent vendor behavior is not declared permanently fixed; further physical reproduction may be needed |
| Temperature display and motion | Codex | Smooth local digit animation restored; modes without a setpoint show an em dash without an invented temperature slider | Delivered in 0.1.3 |
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
| Native gadget illustrations | Codex | The released 0.1.3 baseline used the earlier console and 72-cell solar projection, with on/off scale renders reviewed for that release. The current source has a further console/controller redraw and regular 144-half-cell solar layout, described above | Current revision awaits combined render/native review; 0.1.3 remains the published baseline |
| 3D map shadows and rendering | Codex | Contact shadows, improved masking and directional SceneKit lighting retained | Supported GPU/OS coverage below |
| Metal contact lighting | Codex | Native ray-traced contact pass with fallback; local M4 GPU checks passed | Not full path tracing; hosted GPU checks skip where unsupported |
| Map defaults, controls and toolbar | Codex | See-through collapsed map, consolidated full-map toolbar and smoother plan/3D transitions | No new dependency |
| Activity and page transitions | Codex | Unified six-option Activity filter tray without clipped side pills, filter transitions, text gradients, moving selection keys and scoped page motion refined; native filter tray reviewed and Reduce Motion retained | Broad animation smoothness requires native review |
| Assets → demo home → Back | Codex | Departing demo snapshots retained; native return to Assets reviewed; route fixtures pass | Heading refinement also reviewed and delivered in 0.1.3 |
| Semantic navigation icons | Codex agent | Consistent semantic drawings and selected fills; Climate uses a snowflake; Reduce Motion respected | Further optical review remains possible |
| Floating bottom navigation | Codex | Full-height content scrolls behind the capsule; no inner content cutouts or full-width fade/black band; final controls remain reachable and fixed climate/demo controls clear the dock | Delivered in 0.1.3 |
| Navigation glass preference | Codex | Remembered 0–100% surface opacity, default 55%; foreground remains full opacity; Reduce Transparency/Increase Contrast force a solid surface. Native slider adjusted and restored during review | Delivered in 0.1.3 |
| Menu-bar pill and flash alerts | Codex | Owned status view avoids selection bezel; pill height increased where the menu bar permits; crisp flash edges reviewed and accepted by owner | Delivered in 0.1.3 |
| Stable open-panel position | Codex | Opening anchor retained through status updates; bounded status slot centers artwork; screen clamping and explicit reanchoring preserved; geometry fixtures pass | Native status-update review does not certify every display/menu-bar arrangement |
| Scrolled page heading | Codex | 0.1.3 used a translucent 84pt rounded card with 16pt insets and 35pt overlapping camera/device circles; current source uses 68pt / 12pt / 26.25pt and Activity/Settings symbols; original-title fade and separate accessibility handling. Native Security scroll/return and Activity glass-card/filter-tray review completed | Delivered in 0.1.3; broader manual accessibility coverage below |
| Map and widget accessibility | Codex agents | Keyboard placement and named actions retained; Open full map has its own label/hint, confirmed through native accessibility inspection | Full VoiceOver review and additional machines below |
| Accessible blue and home energy palette | Codex | Rich adaptive blue, white marks on deeper blue and coherent green home-energy surfaces; source-linked normal/Increase Contrast checks pass | Live glass/photos still require visual review |
| Appearance and preference layouts | Codex agents | Immediate Light/Dark/System behavior, clearer widget/notification settings, right-aligned version switch and roomier integration controls | No new dependency |
| Help and support drafts | Codex | Local editable Subject/Message, preserved edits, optional versions off by default, Open mail app and Copy draft; contact@elvisobi.com; no automatic sending | User chooses when to send; actual mail-handler coverage varies |
| Speaker actions and capability routing | Codex agents | Registered capabilities and authoritative responses; idle supported Alexa devices request music on the chosen speaker; approved physical playback heard by owner and stopped | Announcement audibility can depend on DND/device behavior; separate confirmation remains |
| Credential and redirect boundaries | Codex | Home Assistant origin restrictions, redirect handling and session guards; regression checks pass | Ongoing security review, not a complete security certification |
| Home identity and map/scan compatibility | Codex | Unique scan imports and saved home/map compatibility retained; regressions pass | No new dependency |
| Public imagery and usage guides | Codex | Native showcase, refreshed demo-only light/dark/heading guides, connection/use steps, artwork library and explicit static-control provenance; 86 PNG files audited for 0.1.3; current source refresh has 92 | Continue demo-only review for future imagery |
| Memory-only Activity previews | Codex | Explicit memory-only synthetic activity; five isolated regression tests prevent preview fixtures from persisting to runtime stores | Delivered in 0.1.3 |
| Open-source preparation | Codex agents | License/notices, attribution, contributor/security guidance, issue/PR templates, generic examples and independently reviewed public history; final export of 243 files audited | Review every future export and release asset |
| Repository security and CI | Codex | Required PR/build checks, force-push/deletion protection, secret scanning/push protection, private security reports, dependency updates and pinned Actions | Keep protections active; latest batch evidence above |
| Universal build and DMG tooling | Codex agents | Final 0.1.3 universal payload, separate staging, provenance, signatures and disk-image validation; optional notarization workflow retained | Developer ID/notarization input below |
| Preview download | Codex | [0.1.3 preview](https://github.com/obileonardo/hearth-macos/releases/tag/v0.1.3-preview), build `20261015.5`; SHA-256 recorded above. A fresh unauthenticated download matched both the packaged SHA-256 and published checksum. | Developer ID/notarization input below |
| Installed app and source continuity | Codex | Canonical `~/Applications/Hearth.app` updated; existing Apple Development signing retains Keychain trust, one Hearth process verified, older app backed up recoverably. 41 source files synchronized to the original working folder; original Git bookkeeping untouched | Current source follow-up and installation/release validation are recorded above |
| External-drive project relocation | Codex | Working files/history retained; original paths linked | External drive must remain connected |
| Task register and Claude handoff | Codex | Current public source/artifact evidence here and in the 0.1.3 verification record; detailed operational handoff kept private | Keep future work records current |

## Input, hardware and vendor requirements

These are the remaining requirements after the completed 0.1.3 implementation and preview delivery. Existing features and saved data remain intact.

| Item | Needed to finish | Reason |
|---|---|---|
| Developer ID signed/notarized download | Local Developer ID Application certificate and notarization Keychain profile, then accepted submissions/stapling/Gatekeeper checks | Owner offered signing access; distribution credentials are not yet installed/confirmed. Ad-hoc preview is available |
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

The [0.1.3 verification](../docs/release-verification-0.1.3.md) records the current 137-case source batch and artifact. Earlier source batches passed 107, 110 and 129 cases. The historical [0.1.2 verification](../docs/release-verification-0.1.2.md) records its 57-case suite and exact app source/checksum; [0.1.1 verification](../docs/release-verification-0.1.1.md) also remains unchanged. Later changes do not alter an older DMG's provenance.

See [source/release status](../docs/open-source-readiness.md), [navigation](../docs/navigation.md), [widgets](../docs/widgets.md), [release policy](../docs/release-policy.md) and [map lighting](../docs/map-lighting.md). Private records, owner recordings, credentials and household runtime stores are excluded from public Git history.
