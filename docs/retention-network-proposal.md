# Retention and network proposal

**Decision document, not a configuration change.** Existing behavior is preserved. Preparing this proposal did not delete files, inspect personal histories, change permissions, reconfigure Home Assistant, recreate containers or alter network access.

## Current behavior verified in source

| Data or connection | Current boundary |
|---|---|
| Activity timeline | `ActivityLog` stores its index in Hearth's Application Support folder and caps newly added/backfilled entries at 300. Clearing the timeline clears the index; it does not erase the corresponding JPEG files. A later logbook backfill can reintroduce earlier metadata |
| Activity images | Captured images use an event UUID filename in the activity subfolder. They have no age-based cleanup. Notification attachments use a separate temporary copy |
| Familiar faces | Opt-in local Vision processing stores a separate index, crops and feature prints. Existing Forget controls remove learned samples; activity pictures and Home Assistant/vendor history are separate data |
| Display privacy | Blur covers authored image surfaces. It is not deletion, encrypted storage, notification-history erasure or a Home Assistant/vendor retention policy |
| Other saved data | Homes, manual gadgets, imported maps and display/paint choices persist separately. They must not be included in a camera-file cleanup |
| Home Assistant session | Refresh token in Keychain; configured HTTP(S)/WebSocket connection. Plain HTTP does not encrypt traffic. Embedded sign-in web view uses a nonpersistent store and an origin guard |
| Images and icons | Brand icons fetch from `brands.home-assistant.io` and cache locally. External album artwork can be fetched without the Home Assistant bearer token; cross-origin image redirects strip authorization/cookies |
| Manual gadget checks | User-supplied gadget addresses receive TCP reachability checks on their kind's configured ports. A refused connection can mean the host is reachable; this does not authenticate device identity |
| Container example | Home Assistant's example publishes `8123:8123`; the dev profile publishes `8124:8123`. Stable/latest tags are floating; configured DNS uses public resolvers. The optional Eufy bridge has separate state and credentials |
| Optional WidgetKit data | A provisioned App Group can contain one bounded snapshot, excluding tokens, server addresses and camera photographs. It is not a second Home Assistant connection |

Sources: `ActivityLog.swift`, `Faces.swift`, `HAPictures.swift`, `HAAdmin.swift`, `Views/HAWebWindow.swift`, `Views/GadgetsViews.swift`, `Widgets/SharedWidgetSnapshot.swift` and `homeassistant/docker-compose.yml`. See [Security](../SECURITY.md) and [Privacy](../README.md#privacy) for existing disclosures.

## Retention choices

| Option | Benefit | Trade-off / required choice |
|---|---|---|
| Keep current retention | Preserves existing history and files | Storage can grow beyond the 300-item timeline; user manages it |
| Opt-in age limit for activity photos | Bounds future photo storage with an understandable duration | Choose duration and treatment of existing images, referenced records and face samples. Deletion may be irreversible |
| Opt-in age and size limits | Also controls unexpectedly large storage growth | Choose which limit wins, oldest-first behavior and whether event text remains. More policy to explain |
| Manual review and cleanup | Owner reviews count/size and categories before a change | Requires a clear review screen and explicit confirmation; no automatic space recovery |

**Recommended proposal:** preserve current behavior by default. Add a future storage review showing activity-photo count/size and separate face data, then offer an explicit opt-in photo age limit (30 days is a proposed starting choice, not an implemented default). Keep event metadata and learned faces independent unless the owner explicitly chooses otherwise. Do not delete Home Assistant/vendor records or touch scans, homes, gadgets, Keychain or settings.

Before implementing deletion, agree the age/size policy, existing-file treatment, and whether a recoverable holding area is desired. Design and test with temporary fixtures: paths must resolve inside the intended activity-photo root; reject symlinks/foreign paths; recheck references after asynchronous captures; preserve active/new files; make a dry run list/count/size first; commit index changes atomically; report partial failures. A recoverable holding area needs its own expiry and disk budget, so it cannot promise immediate space recovery. Never infer that removing the index erased the images or that forgetting faces erased camera history.

## Network and container choices

| Option | Suitable use | Compatibility cost / decision |
|---|---|---|
| Preserve current reachable LAN setup | Household access and integrations currently working | Existing exposure remains; keep credentials local and document actual firewall/router policy |
| Loopback-bound isolated dev service | Synthetic development accessed only from this Mac | Other machines cannot reach the dev instance; independently verify the Compose override before any recreate |
| Narrow LAN interface / firewall policy | Limit clients to intended devices | Need intended client list, correct host/VM interface behavior and discovery requirements; a macOS/VM deployment must be tested rather than assumed |
| Authenticated HTTPS route | Protect traffic on a shared or remote network | Need the intended hostname, certificate/trust and access policy; do not disable certificate verification |
| Pin images by reviewed digest | Reproducible upgrades and rollback candidates | Need architecture-specific compatibility, current image inventory, backups, patch-review cadence and a maintenance window |

**Recommended proposal:** keep the live installation unchanged until its inventory and recovery plan are approved. Prefer a separate loopback-bound dev instance, HTTPS for traffic across shared networks, and reviewed image pins for the next planned maintenance. The proposal does not assume the Mac host's firewall or Docker bridge provides integration discovery or vendor-cloud isolation. Blocking cloud/DNS traffic can break sign-in, speakers, cameras or pairing.

### Installation-specific implementation gate

1. Owner chooses intended clients/remote access, dev exposure, DNS policy and maintenance window. Identify required multicast/discovery and vendor-cloud paths for the actual integrations.
2. Record current image identifiers/digests, architecture, mounts, ports and Compose inputs privately. Never publish environment values, tokens or raw configuration inventories.
3. Take and validate a recoverable configuration/state backup, including Home Assistant and any bridge state. Image rollback alone does not reverse data/schema migrations.
4. Prepare an isolated candidate and rendered configuration with secrets redacted. Test authentication, WebSocket reconnect, live video, vendor sign-in, discovery, speaker playback and state freshness before touching the working service.
5. Make a single approved change during the maintenance window; verify the agreed workflows and retain the previous configuration/image reference. Roll back with a compatible data snapshot if needed; do not blindly downgrade migrated state.

## Decisions still required

| Owner input | Independent preparation already possible |
|---|---|
| Keep files indefinitely, manual cleanup, or a duration/size limit; include existing images? | Source data-flow inventory, candidate UI/fixture design and non-destructive dry-run plan |
| Whether faces/event text have separate lifetimes; backup/holding-area preference | Document category boundaries and restoration cases |
| LAN-only versus remote access; intended clients, trusted hostname and DNS policy | Draft configuration alternatives and compatibility checklist |
| Acceptable restart window, backup destination and upgrade/rollback policy | Identify required inventory fields and validation order |

No approval is inferred from this proposal. Source publication and routine app fixes do not authorize deleting personal data or changing a working installation's network topology.
