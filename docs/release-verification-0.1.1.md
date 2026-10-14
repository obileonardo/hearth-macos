# Hearth 0.1.1 preview verification

Recorded 14 October 2026. Download: [versioned GitHub prerelease](https://github.com/obileonardo/hearth-macos/releases/tag/v0.1.1-preview).

| Check | Result |
|---|---|
| Public app source | `7f42c76831f8320ad73597e9db34bb95c3915196`; 191 reviewed source files, independent initial history; private runtime stores and development history excluded |
| Source provenance | All 61 app Swift files match the compiled reviewed candidate |
| Hosted checks | [Public run 38534020918](https://github.com/obileonardo/hearth-macos/actions/runs/38534020918): release compile, 36 XCTest cases (zero failures; two GPU skips), shell syntax and universal optional WidgetKit compile passed |
| Local GPU checks | Apple M4 Metal ray-traced occlusion, transformed geometry, transparency/hidden exclusion and invalid-input guards passed |
| Local model/snapshot checks | Temporary assertion runner passed isolated fixtures; local Command Line Tools lack XCTest, so this is separately reported from hosted XCTest |
| Universal binary | Both arm64 and x86_64 architecture checks passed; macOS 14 deployment target |
| DMG | Embedded CRC checks passed; mounted read-only and reviewed |
| App signature | Strict/deep ad-hoc signature verification passed; not Developer ID signed or notarized |
| Payload | App, Applications shortcut, installation instructions and BuildInfo.txt only; no personal configuration, saved homes or camera history |
| SHA-256 | `9e60647485e725d91df4c216a3a81fab877330dc05f4fa21f76ec6028536873a` |
| Repository rules | Active main rule requires PR and official GitHub Actions build; disallows force pushes and deletion |
| Security settings | Secret scanning and push protection, private vulnerability reporting, dependency alerts/security fixes, read-only Actions token and pinned approved publishers enabled |
| Native desktop smoke review | Existing saved Overview data loaded; resize action changed dimensions and was reversed; Home link opened Rooms; movement actions exposed |

The preview omits the unprovisioned WidgetKit extension. Its source and build tooling are included; gallery registration needs valid signing/provisioning. This record does not claim physical-device tests, Intel runtime validation, all supported macOS versions, a complete security audit or full VoiceOver coverage. A notarized download needs the maintainer's local Developer ID and notarization setup.

Subsequent source commits may update documentation or developer tooling. This DMG remains tied to the exact source commit above.
