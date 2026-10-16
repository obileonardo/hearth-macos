# Third-party notices

Hearth's original source is licensed under [MIT](LICENSE). It has no external Swift package dependencies; Apple system frameworks and SF Symbols are provided by macOS under Apple's terms.

## Optional Home Assistant patches

Scripts in `homeassistant/patches/` quote small portions of the following projects as match anchors and modify their installed files on the user's machine. They do not bundle the complete libraries. Those excerpts retain their upstream licenses rather than being relicensed under Hearth's MIT license.

| Script | Upstream project | License | Attribution |
|---|---|---|---|
| `amazon_two_page_signin.py` | [aioamazondevices](https://github.com/chemelli74/aioamazondevices), sign-in code from the 16.3 series | [Apache-2.0](https://github.com/chemelli74/aioamazondevices/blob/main/LICENSE) | Simone Chemelli and contributors |
| `lg_switch_case.py` | [Home Assistant Core](https://github.com/home-assistant/core), LG ThinQ switch code | [Apache-2.0](https://github.com/home-assistant/core/blob/dev/LICENSE.md) | Home Assistant contributors |
| `apple_tv_unicast.py` | [Home Assistant Core](https://github.com/home-assistant/core), Apple TV integration | [Apache-2.0](https://github.com/home-assistant/core/blob/dev/LICENSE.md) | Home Assistant contributors |
| `eufy_identity_person_name.js` | [eufy-security-client](https://github.com/bropat/eufy-security-client), push and device code from the 4.1 series | [MIT](https://github.com/bropat/eufy-security-client/blob/master/LICENSE) | Copyright (c) 2021–2024 bropat |

Each script describes its change and guards against a changed upstream source layout. Consult its instructions before applying it to a compatible installation. The Compose file references Home Assistant's Apache-2.0 image and the [eufy-security-ws](https://github.com/bropat/eufy-security-ws) MIT image; their source, dependencies and license notices remain with their respective projects. Other Home Assistant integrations are installed separately and retain their own licenses.

The complete [Apache-2.0 license](docs/licenses/Apache-2.0.txt) and [eufy-security-client MIT notice](docs/licenses/eufy-security-client-MIT.txt) accompany the quoted anchors. The scripts change the installed upstream code as described in their headers; preserve upstream notices in those files.

## Runtime images and product names

Integration icons can be fetched from [Home Assistant Brands](https://github.com/home-assistant/brands). Album artwork and camera imagery come from the user's integrations. These resources are not Hearth-owned art and are not included under Hearth's MIT license.

The native device illustrations are drawn by Hearth's SwiftUI Canvas code with AI assistance during development. The current README hero, `docs/art/hearth-native-showcase.png`, is rendered directly from those app components. The older `hearth-showcase.png` is an archived AI-composed raster image; its references and prompts remain in [artwork notes](docs/art/showcase.md). The [asset and excerpt register](docs/provenance-register.md) distinguishes known sources from unresolved ownership and revision evidence. Brand and model names identify compatible products; their use does not imply endorsement. Hearth is an independent project, unaffiliated with Home Assistant, Apple, Amazon, LG, Ring, Eufy, Bambu Lab, Sony or the vehicle manufacturers named in the app. Product names, logos and other marks belong to their respective owners. The MIT license does not grant trademark rights.

## Apple interface symbols

App interface code requests SF Symbols from macOS. Some interface-preview assets also show these symbols. Apple frameworks, fonts and symbols retain their respective terms; Hearth's MIT license does not relicense them. Review standalone marketing use against Apple's [SF Symbols guidance](https://developer.apple.com/sf-symbols/) and applicable developer agreements before redistributing those assets separately.
