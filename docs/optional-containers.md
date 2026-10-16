# Optional Home Assistant containers

Hearth itself needs no container. These examples are for people choosing to self-host Home Assistant; they do not describe a required Hearth backend. This document makes no changes to an existing installation.

## Current example and limits

| Service | Source example | Purpose | Current limitation |
|---|---|---|---|
| `homeassistant` | `ghcr.io/home-assistant/home-assistant:stable` | Optional main Home Assistant | Mutable tag; not an immutable, audited transitive dependency inventory |
| `homeassistant-dev` | Same `stable` image, `dev` profile | Separate fixture server, host port 8124 | No automatic onboarding, token or device seeding |
| `eufy-security-ws` | `bropat/eufy-security-ws:latest`, `eufy` profile | Optional Eufy bridge | Mutable tag and retired upstream; account/pairing compatibility depends on the installation |

The checked-in Compose file publishes Home Assistant ports without a loopback address. Do not assume it is restricted to this Mac; exposure depends on the container VM, host and network. It also uses fixed service/container names. Review conflicts and bindings before use. Credentials belong in private local files, never the source repository.

The `stable` and `latest` labels do not establish an exact image, platform manifest, SBOM, license set or advisory result. No installed image was pulled, replaced, restarted, scanned through a third-party upload service or declared vulnerability-free during the documentation review.

## Eufy maintenance status

As reviewed on 2026-10-15, the upstream [bridge](https://github.com/bropat/eufy-security-ws) and [client](https://github.com/bropat/eufy-security-client) repositories were archived on 2026-09-12. Their deprecation notices point to [mega-yfue/eufy-sdk](https://github.com/mega-yfue/eufy-sdk). This is a maintenance warning, not proof of a specific vulnerability or a compatible drop-in replacement.

Keep an existing working bridge and pairing intact. A successor needs a separate review of its license, authentication, exposed WebSocket/API contract, integration support, event names, camera streaming and rollback. Do not migrate, create an additional camera login or unpair devices as a source cleanup task.

## Proposed isolated update workflow

Before an installation change, the operator should approve the scope and private backup location. A repository commit does not back up credentials, pairings, Home Assistant storage or camera data.

1. Record the existing image reference, resolved registry digest, platform, Compose configuration and data locations privately. Avoid sharing raw `docker inspect` or environment output, which can contain secrets.
2. Obtain a verified backup of the affected private data only with permission. Confirm how to restore the current image and data together.
3. Select a new, disposable data directory, distinct service names and unused ports. For a Mac-only experiment, propose loopback bindings such as `127.0.0.1:8124:8123`. Verify that the test environment cannot command the working home.
4. Resolve the candidate image to an immutable `registry/repository@sha256:<digest>` reference for the intended architecture. Record the actual version, digest, provenance, upstream release notes, component licenses and available advisory results. Do not publish an invented digest or infer the currently running image from a mutable tag.
5. Review a separate Compose proposal, including any DNS, bridge access and persistence requirements. Do not edit the active Compose file in place.
6. Run onboarding and the [synthetic vehicle fixture](local-development.md#optional-home-assistant-fixtures). Review source patches first; [maintenance tools](../homeassistant/patches/README.md) are optional and require explicit apply mode.
7. Only after separate approval, validate real integrations with a bounded test and a restoration plan. Compare status and settings before/after. Keep physical-device checks distinct from fixture success.

No pinned-image claim is made until an exact manifest and its evidence are recorded. No operational migration is authorized by these instructions alone.
