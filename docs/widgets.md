# Widgets

Hearth puts its widgets on the desktop itself (Settings, Desktop widgets). They are ordinary
Hearth windows that sit just above the desktop icons, on every Space, beneath your app windows.
Click the content once to open its page. Drag the small handle at the top to move it,
or the grip at the bottom right to resize it. Position and size are saved. The overview
reflows into two rows when narrowed. Each overview section opens its own page.
The move handle exposes assistive actions for left/right/up/down in 20-point steps;
these stay on the current display and save the position. The resize grip exposes
an adjustable accessibility action. Ordinary mouse dragging can still move a widget
between displays. Disabling a widget clears any unfinished drag state.
They observe Hearth's Home Assistant connection and activity log while Hearth is running.
The small connection indicator distinguishes live readings from disconnected values.

| Widget | Initial size | Shows |
|---|---|---|
| Overview | 664 x 170 | Selected/automatic AC, newest person or doorbell event, energy when connected; otherwise current music or home device/room counts |
| Climate | 170 x 170 (small) | Set temperature, mode, room temperature |
| Recent activity | 344 x 170 | The newest person or doorbell event across the home, with its picture when available |
| Energy | 344 x 170 (medium) | Battery charge, solar power, the home's power now |

## How the content was chosen

Claude's initial desktop implementation selected four widget families around Hearth's existing
climate, security/activity and energy features. The transcript and implementation do not show
a user research study or a personalized ranking of this home's needs. The overview combined
all three, even when energy was not connected. Its original “Front door” name was misleading:
the query was already across the home, not filtered to one door.

Settings lets the owner enable each family independently and choose an AC. Automatic chooses
an available running household AC first, then another available household AC; vehicle cabin
climate is excluded. A chosen AC remains selected even when offline, with its availability shown.
A removed selection falls back to automatic. The standalone Energy widget is
retained when explicitly enabled, including its connection/setup state. No energy readings or
speaker synchronization measurements are fabricated.

The overview's recent activity section uses compact text to give the event room to read;
the separate Recent activity widget retains its camera picture and existing privacy blur.

## macOS widget gallery target

The optional WidgetKit target is now implemented in `WidgetExtension/`. It includes four
widget types, a timeline provider, small/medium families and a larger overview, and links
to the corresponding pages in Hearth. `scripts/build-widgets.sh --universal` builds both
Apple silicon and Intel slices without installing or registering the extension.

Gallery snapshots use an entitlement-authorized App Group. The app writes a small atomic
JSON document; the extension does not connect to Home Assistant. The schema includes
display names, one climate entity ID, selected readings, the newest activity title/time,
current music metadata and device/room counts. It excludes tokens, server addresses,
account information, raw entity attributes and camera photographs. The desktop widgets
retain their existing pictures and privacy blur.

`WidgetSnapshotPublisher` observes the same household AC selection, entity state and
activity feed as the desktop widgets. Writes are debounced; timeline reload requests are
limited to once per minute. WidgetKit controls the refresh budget and delivery time, so
gallery widgets are snapshots rather than a continuous live stream. A timeline entry marks
the snapshot stale after five minutes. Desktop windows continue to observe live values.

Each gallery link uses the `hearth://widget/` URL scheme. The app accepts only known page
routes or a valid climate entity ID. Credentials, arbitrary URLs and service commands are
rejected. Clicking opens Hearth's existing panel; it does not send a hardware command.

### Unsigned development build

```sh
scripts/build-widgets.sh --universal
HEARTH_INCLUDE_WIDGETKIT=1 HEARTH_WIDGET_UNSIGNED=1 HEARTH_SIGN_IDENTITY=- \
  scripts/build.sh --debug --no-install
```

The second command stages an ad-hoc-signed extension and host for build inspection only.
It does not install the app, register a plug-in, grant App Group access, or establish that
widgets appear in the macOS gallery. Default app and DMG builds keep the working desktop
widgets and omit this unprovisioned extension.

`scripts/render-widget-previews.sh` renders synthetic light/dark, populated and empty/stale
fixtures for every supported family. It renders the authored surface outside WidgetKit;
its system Link wrappers are represented by their exact contents because ImageRenderer
cannot rasterize a system link outside its host. These images verify layout, not gallery
registration or system interaction.

### Signed gallery build inputs

Enable `HEARTH_INCLUDE_WIDGETKIT=1` and provide:

- `HEARTH_WIDGET_APP_GROUP`: the shared group authorized for both app and extension.
- `HEARTH_WIDGET_SIGN_IDENTITY`: the matching signing identity.
- `HEARTH_HOST_PROFILE`: a macOS profile for `com.elvisobi.hearth`.
- `HEARTH_WIDGET_PROFILE`: a macOS profile for `com.elvisobi.hearth.widgets`.

`scripts/embed-widgets.sh` validates supplied profiles' platform, expiry, bundle IDs,
team and group authorization, embeds them, signs the extension first, and supplies host
entitlements to `build.sh`. Only the extension enables App Sandbox; the host retains its
existing unsandboxed features. The script never requests certificates, creates profiles,
uploads data or registers the extension with the system.

Apple also supports team-prefixed macOS App Groups without a restricted group profile;
see [Configuring app groups](https://developer.apple.com/documentation/xcode/configuring-app-groups)
and [Accessing app group containers](https://developer.apple.com/documentation/xcode/accessing-app-group-containers).
This does not establish whether a particular WidgetKit extension will register successfully.
Gallery registration, actual provider execution, signed App Group access and distribution
remain unverified until valid signing/provisioning inputs are available. The signed input
path has not been exercised with real profiles; the universal unsigned target and staging
integration have been built locally.

Provider behavior follows Apple's [TimelineProvider](https://developer.apple.com/documentation/widgetkit/timelineprovider)
and [Keeping a widget up to date](https://developer.apple.com/documentation/widgetkit/keeping-a-widget-up-to-date)
guidance. Widget URLs follow [Creating a widget extension](https://developer.apple.com/documentation/widgetkit/creating-a-widget-extension).

## Claude's earlier gallery registration experiment

A WidgetKit extension builds without Xcode: a SwiftPM or swiftc executable whose `@main` is a
`WidgetBundle`, packed as `Hearth.app/Contents/PlugIns/HearthWidgets.appex` with
`NSExtensionPointIdentifier` = `com.apple.widgetkit-extension` and the app sandbox entitlement.
Tested on macOS 27 with the Command Line Tools and the 26.5 SDK (13 Oct 2026):

1. It compiles, signs with the Apple Development certificate and registers:
   `pluginkit -m -p com.apple.widgetkit-extension` lists it.
2. chronod, which feeds the widget gallery, then drops it:
   `[com.apple.chrono:descriptor] Requested to add extension, but purging instead because we
   shouldn't cache it: <WidgetExtension ... isApple: false>`. Same result from ~/Applications
   and with the Info.plist keys Xcode adds (`CFBundleSupportedPlatforms`, `DT*`).
3. Real third-party widgets carry `com.apple.application-identifier` and
   `com.apple.developer.team-identifier` entitlements, which come from a provisioning profile.
   Adding them without a profile stops registration entirely: pkd logs
   `No plugins found to match query` and pluginkit no longer lists the extension.

Claude's experiment identified a **macOS** development provisioning profile as its next step,
for an App ID such as
`com.elvisobi.hearth.widgets`, made with Xcode or in the Apple Developer portal.
An iOS profile cannot be used for this macOS extension. With a valid macOS profile embedded (`embedded.provisionprofile`) and
an App Group shared between the app and the extension, the WidgetKit route can be investigated
again. Gallery distribution remains unverified; these desktop windows are the working implementation.
