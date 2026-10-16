# Local development without changing a working home

Hearth is a macOS SwiftUI app. Its executable talks to the Home Assistant server you configure; it does not require a Hearth backend, database server, package registry account or Docker to build.

## 1. Get the reviewed source

```sh
git clone https://github.com/obileonardo/hearth-macos.git
cd hearth-macos
scripts/build.sh --debug --no-install
```

Use Xcode 26 or compatible Command Line Tools with a macOS 26 SDK. `HEARTH_SDKROOT` selects an installed SDK. The build script selects the compatible macOS 26.5 SDK with Command Line Tools when available; it does not change global Xcode selection. The deployment target is macOS 14, which is distinct from the SDK needed to compile guarded APIs.

The command builds `build/Hearth.app` without installing it. Set `HEARTH_APP_OUTPUT` to a new path ending in `/Hearth.app` when preserving an earlier generated build. Output symlinks and running output bundles are refused. Release builds install by default unless `--no-install` is supplied. The installer requires the destination app to be stopped, verifies a staged replacement and retains the previous app as a hidden sibling backup; it does not erase runtime data. Keep the reported backup path for recovery. Do not open two interactive copies with the same bundle identifier or replace somebody's operational app during a documentation change.

## 2. Review offline screens

```sh
build/Hearth.app/Contents/MacOS/Hearth --render-preview /tmp/hearth-previews-new
```

Choose a new output directory. This command renders synthetic sample stores and exits before connecting to Home Assistant or requesting notification permission. Activity is memory-only, and no saved camera image or face reference is loaded. It does not exercise real devices or prove that a native control works. See [documentation imagery](screenshots/README.md).

## Authentication and isolation

The app's current username/password flow cannot finish Home Assistant MFA. Keep MFA enabled. Do not disable it as a workaround.

For development against a **separate test server**, the app accepts `HA_URL` and `HA_TOKEN`. A token has its account's privileges: create it in that test server's profile, keep it in your local process environment, and never commit it or paste it into an issue. This is a developer path, not an MFA implementation or a reason to copy production credentials. Remove these variables before testing normal sign-in.

Without these variables, the app can reuse the existing Keychain session for its configured server. File overrides isolate documents; they do not alone isolate authentication. Do not launch an interactive developer build against a working home just to inspect sample UI. The [offline exporter](#2-review-offline-screens) is the safe option for screenshots.

| Override | Isolated data |
|---|---|
| `-homesFile <path>` | Home list and links |
| `-gadgetsFile <path>` | Manually added gadgets |
| `-mapsFolder <path>` | Imported maps and placement files |
| `-facesFolder <path>` | Familiar-face samples |
| `-activityFolder <path>` | Activity index and pictures |

Keep every override in a disposable private directory. Changing display preferences in an interactive app can still change UserDefaults; the document paths do not create a separate macOS app identity.

## Optional Home Assistant fixtures

The supplied Compose `dev` profile starts a second Home Assistant service; it does not copy the custom integration, create an account, obtain a token or add sample devices. It is optional. Review the [container isolation notes](optional-containers.md) before starting anything.

For a new disposable setup, the exact sequence is:

1. Copy `homeassistant/.env.example` to `homeassistant/.env` only if no configured file already exists. Choose a new absolute `HEARTH_DATA` directory. Do not reuse a working configuration directory.
2. Start **only** `homeassistant-dev` with the documented profile. Existing service names/ports must be checked first; do not restart an operational installation.
3. Open `http://localhost:8124` and complete Home Assistant onboarding with a test account.
4. Copy `homeassistant/dev/vehicle-test/custom_components/hearth_vehicle_test` into the disposable server's `/config/custom_components/` directory.
5. Restart that disposable dev service, then add **Hearth vehicle test** through **Settings → Devices & services → Add integration**.
6. Confirm the Test Model Y, Test Wallbox and Test Automower appear in that server. Create a test-server token only if using the developer token path.

The [fixture README](../homeassistant/dev/vehicle-test/README.md) lists the simulated entities and commands. Those actions must target the disposable server. Entity shapes and a successful simulation do not establish compatibility with an actual vehicle, charger or mower.

## Checks before a contribution

Run `swift test` with full Xcode selected, and record the actual result. Command Line Tools can build the app but may lack the XCTest runtime. [Model regressions](model-regressions.md) explains fixture scope and GPU-dependent skips. Inspect changed documentation links, light/dark rendering, keyboard navigation and relevant accessibility settings. Report unavailable hardware/OS checks as not run.

No setup instruction requires deleting an existing data directory, resetting pairings, changing network bindings, replacing a Home Assistant image or issuing live device commands.

Optional maintenance tools default to source checks and need explicit apply mode; read the [patch guide](../homeassistant/patches/README.md). Their isolated regression checks use `python3 -m unittest discover -s Tests/MaintenancePatches -v`. They must not run against working dependencies merely to test a contribution.

## Upgrading a saved sign-in

New saved sessions are bound to the Home Assistant origin in one Keychain record. An older unbound saved token is retained privately but is not sent until you confirm the already configured server locally or sign in again. Review that address in Hearth; do not paste it or a token into an issue. A failed new sign-in keeps the previous configuration and credential intact. A development `HA_URL` selecting a different server cannot silently reuse the old saved session.

Signing out clears the temporary Home Assistant web session as well as the app session. This affects Hearth's own window, not other browsers or device pairings.

## Environment inputs

None are required for the normal app sign-in flow. Examples contain placeholders, not usable credentials.

| Input | Scope | Required / sensitivity |
|---|---|---|
| `HA_URL` | Developer app connection override | Optional; server address can be private |
| `HA_TOKEN` | Developer app bearer credential | Optional; secret, for the selected test server only |
| `HEARTH_SDKROOT`, `SDKROOT` | Build SDK path; explicit Hearth choice takes precedence | Optional; local path, not a credential |
| `HEARTH_APP_OUTPUT` | Generated bundle destination, ending in `/Hearth.app` | Optional; use a new path for review |
| `HEARTH_APP_VERSION`, `HEARTH_BUILD_NUMBER` | App/widget bundle versions | Optional public release metadata |
| `HEARTH_SIGN_IDENTITY` | Existing local signing identity, or `-` for ad-hoc | Optional for builds; not a private key; do not export the certificate/key |
| `HEARTH_SOURCE_COMMIT` | DMG manifest source override | Optional public commit; use only when provenance is known |
| `HEARTH_INCLUDE_WIDGETKIT`, `HEARTH_WIDGET_UNSIGNED` | Optional gallery target / inspection mode | Optional flags; unsigned mode does not grant App Group access |
| `HEARTH_WIDGET_OUTPUT`, `HEARTH_WIDGET_UNIVERSAL` | Extension output and architecture selection | Optional tooling inputs |
| `HEARTH_WIDGET_HOST_APP`, `HEARTH_WIDGET_HOST_ENTITLEMENTS` | Staging host and generated entitlements paths | Required by the embedding helper; usually set by `build.sh` |
| `HEARTH_WIDGET_APP_GROUP`, `HEARTH_WIDGET_SIGN_IDENTITY` | Gallery entitlement and local identity | Required for the signed gallery path; project-specific configuration |
| `HEARTH_WIDGET_PROFILE`, `HEARTH_HOST_PROFILE` | Local provisioning-profile paths | Required for signed gallery builds; keep profile files private |
| `HEARTH_DATA`, `TZ` | Optional Home Assistant Compose data directory/timezone | Required by a chosen setup's configuration; path may be private |
| `USERNAME`, `PASSWORD` | Optional Eufy bridge account inputs in a private env file | Secret credentials; never place real values in source examples |
| `COUNTRY`, `TRUSTED_DEVICE_NAME` | Optional Eufy bridge region/device label | Configuration; labels can be identifying |

`HOME`, `TMPDIR` and normal toolchain/PATH settings are inherited system inputs, not application secrets. Notarization uses the existing Keychain profile passed to `--notary-profile`; no account password is accepted as a packaging argument. See [widgets](widgets.md) and [DMG packaging](../releases/dmg/README.md) for the full optional signing flow. Signing/provisioning access is not required to review offline screenshots.
