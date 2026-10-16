# Source and asset provenance register

Baseline reviewed 2026-10-15; console/solar visual-reference notes added 2026-10-16. This register identifies known sources and remaining evidence gaps; it is not a legal opinion or a claim that a repository author necessarily owns every input. [MIT](../LICENSE) is the intended license for original code whose rights permit it. Third-party material keeps its own terms.

## Original code and generated documentation

| Material | Evidence / generation path | Distribution and remaining review |
|---|---|---|
| `Sources/Hearth/`, tests and original tooling | Git-tracked Swift, Metal, Python, JavaScript and shell code; Claude/Codex assistance credited in README | Root license names 2026 Elvis Obi. The owner confirmed authority for original code and illustrations on 2026-10-15; documented third-party terms remain separate. Agreements were not independently supplied or reviewed |
| `Resources/AppIcon.icns`, `docs/art/AppIcon-1024.png`, menu-bar image exports | Native icon/menu art generators in `Sources/Hearth/Views/ArtExporter.swift` and `scripts/render-art.sh` | Generated from project drawing code; any Apple symbols, fonts and product marks retain separate terms |
| `docs/art/devices/*.png`, `devices.png` | Native `DeviceArt`, `EnergyArt`, vehicle drawing code and `ArtExporter` | Illustration code is tracked; model names/shapes may identify third-party products. No manufacturer endorsement or trademark license is implied |
| `docs/art/hearth-native-showcase.png` | `PreviewProductShowcase` in `PreviewExporter.swift`, using actual AC/camera/speaker components | Current README hero; native render, not the archived generated raster scene |
| `docs/screenshots/*.png` | `PreviewExporter.swift` sample stores and explicit documentation fallback controls | Synthetic data only; no home recording, account, camera photo or face sample. Metadata/pixels require review for each refresh. See [image register](screenshots/README.md) |
| `docs/art/hearth-showcase.png` | Archived AI raster composition, built-in image tool, 2026-10-14; prompts and image references in [showcase notes](art/showcase.md) | No longer the README hero. Source references are project image exports. Tool terms/account agreement and rights in all original inputs were not independently supplied; owner review remains necessary before representing unrestricted standalone art rights |
| Apple frameworks, system fonts and SF Symbols in UI previews | Supplied by the macOS SDK/runtime | Not covered by Hearth MIT; review [Apple SF Symbols guidance](https://developer.apple.com/sf-symbols/) and applicable agreements for separate marketing redistribution |
| Runtime brand icons, media artwork and camera/face images | Home Assistant Brands or the user's integrations/data | Not bundled as Hearth-owned assets. Do not copy them from a working installation into public documentation |

No external font files, recorded audio/video, datasets or photographed camera images are required by the reviewed source distribution. The register does not infer the rights of an unknown earlier reference image or copied snippet; report additional origins when discovered.

## Console and solar visual-reference pass — 16 October 2026

The current native drawing revision consulted the following primary visual references:

| Reference | What it informed | Publication boundary |
|---|---|---|
| [Sony PS5 console product page](https://direct.playstation.com/en-us/buy-consoles/playstation5-console-1-tb) and its console/controller product photograph | Slim-style console proportions, curved split covers, recessed front and lower disc-drive shoulder | Reference photography remains Sony material; no reference pixels, product photograph or manufacturer drawing code were added to Hearth |
| [Sony DualSense controller product page](https://www.playstation.com/en-us/accessories/dualsense-wireless-controller/) and its original white controller photograph | Tapered white grips, dark central bridge, touchpad, stick and directional/action-button placement | The illustration is defined by native SwiftUI paths; no controller photograph is bundled and no endorsement or trademark rights are implied |
| [Canadian Solar HiKu CS3W-P datasheet](https://www.canadiansolar.com/wp-content/uploads/2019/12/Canadian_Solar-Datasheet-HiKu_CS3W-P_EN.pdf) | Regular 144-half-cell arrangement, described as two 12×6 sections, for a landscape module illustration | No datasheet, manufacturer artwork or product logo is bundled. The framed module and mounting supports are illustrative, not a model-specific installation or engineering specification |

These references informed new code geometry and restrained materials; they do not make the illustrations manufacturer-certified or establish the rights to redistribute reference media. The existing MIT scope, third-party notices and trademark limits remain unchanged. Final renders, native review and refreshed documentation exports for this revision must be recorded separately after they actually run; this provenance entry does not record a visual review result.

## Quoted maintenance excerpts

The app binary does not link or bundle these optional Home Assistant libraries. Scripts under `homeassistant/patches/` contain matching excerpts and replacement code for a separately installed upstream dependency. The scripts must retain those upstream notices even where the app's original code is MIT.

| Local script | Fixed upstream comparison | Evidence and exact limits | Applicable notice |
|---|---|---|---|
| `amazon_two_page_signin.py` | [aioamazondevices v16.3.0, `509d316cbb1765d1caae819774d75b66f5898172`](https://github.com/chemelli74/aioamazondevices/tree/509d316cbb1765d1caae819774d75b66f5898172) | Script identifies the 16.3 series. Reference license located; exact original `login.py` revision and complete quoted-anchor match remain unverified. This is not a certified compatibility pin | [Apache-2.0](licenses/Apache-2.0.txt); Simone Chemelli and contributors |
| `apple_tv_unicast.py` | [Home Assistant Core 2026.10.0, `6a811d3359c7b2076dc9e1cf900843a129c044af`](https://github.com/home-assistant/core/tree/6a811d3359c7b2076dc9e1cf900843a129c044af/homeassistant/components/apple_tv) | Both `config_flow.py` and `__init__.py` matching anchors present. This comparison does not establish which revision originally supplied the excerpt or validate an installed system | [Apache-2.0](licenses/Apache-2.0.txt); Home Assistant contributors |
| `lg_switch_case.py` | [Home Assistant Core 2026.10.0, same fixed revision](https://github.com/home-assistant/core/blob/6a811d3359c7b2076dc9e1cf900843a129c044af/homeassistant/components/lg_thinq/switch.py) | `on_command` and `off_command` anchors present; original import revision not recorded. A source match is not a real LG control check | [Apache-2.0](licenses/Apache-2.0.txt); Home Assistant contributors |
| `eufy_identity_person_name.js` | [eufy-security-client 4.1.0, `10155f572a0f261acb207c76edc17e2cae78de90`](https://github.com/bropat/eufy-security-client/tree/10155f572a0f261acb207c76edc17e2cae78de90) | Corresponding markers present in `src/push/service.ts` and `src/http/device.ts`; exact compiled JS/package artifact and original excerpt revision not established. Script identifies the 4.1 series | [MIT copyright notice](licenses/eufy-security-client-MIT.txt); bropat |

Upstream root `NOTICE` requests at the listed comparison revisions returned not found. This does not establish absence of notices in every subdirectory or package artifact. Before distributing larger upstream portions or a container, review the exact package/image contents and preserve any additional notices. The existing full Apache license and Eufy MIT notice accompany these small excerpts. Changes are described in script headers and the [patch guide](../homeassistant/patches/README.md).

## Dependency and lifecycle scope

`Package.swift` has no external Swift package dependencies. Apple system frameworks are not relicensed. Optional containers have their own transitive dependencies and licenses; mutable Compose tags are not a complete inventory. See [container lifecycle and pinning](optional-containers.md). No full container SBOM, transitive license clearance or installed-image advisory scan is claimed.

## When adding or refreshing an asset

Record its path, source/generator and revision, reference inputs, applicable terms, required attribution, whether it contains real data, and verification limits. Preserve prompt history for generated raster artwork. Review pixels and metadata before selecting documentation exports. Do not describe an AI tool's involvement as proof of either ownership or infringement. Obtain owner clarification for uncertain rights before making an unrestricted redistribution claim.
