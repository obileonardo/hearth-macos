# Using Hearth

Hearth brings a Home Assistant installation into the Mac menu bar. It reads the entities and registries your server exposes; available controls depend on the integration, model and permissions.

## Connect your own server

1. Install the preview or [build without replacing an existing app](local-development.md).
2. Open Hearth from the menu bar and enter the address of your Home Assistant. Prefer HTTPS on shared or remote networks.
3. Sign in with your Home Assistant account. MFA completion is not supported in this preview; keep it enabled and wait for supported onboarding rather than weakening the account.
4. Add integrations and assign devices to rooms in Home Assistant. Hearth reads that arrangement.

![Illustrated sign-in with a generic server and an empty password](screenshots/guide-connect-light.png)

This image is a static illustration of sign-in controls, not a real account. Passwords are not saved; the refresh token is stored in Keychain.

## Choose a destination

| View | What it organizes | Typical next action |
|---|---|---|
| Climate | Individual climate entities | Open a unit; adjust a supported set point or mode |
| Security | Cameras and alarm systems | Open a live camera, inspect an event or use an exposed alarm control |
| Rooms | Home Assistant rooms and their devices | Browse an overview or select a room in the interactive layout |
| Assets | Homes, energy, vehicles, gadgets and speakers | Open a family or a specific asset |
| 3D map | A demo house or your imported scan | Select a floor; place a device; switch 3D/Plan |
| Activity | People, doorbell, motion, alarm and climate events | Filter the timeline and adjust notification preferences |
| Settings | Connection, appearance, navigation, widgets and help | Choose glass opacity or create a support draft |

## Control a device

Open the device itself rather than assuming every card offers the same functions. Online status, supported modes and exposed actions come from Home Assistant. A service accepting a request does not prove that a physical device carried it out. When an action fails, inspect the reported state and test the same action in Home Assistant before changing the installation.

![Sample climate controls in dark appearance](screenshots/guide-climate-dark.png)

Climate numbers are sample readings. A unit may expose cooling without heating, a different temperature step, or fewer fan/swing options. Unavailable functions are not invented.

## Browse and play speakers

Open **Assets → Speakers** and choose grid or list. Group labels describe the integration's reported group, while each card shows its room and state. Playback and announcements depend on the speaker integration; availability in an offline screenshot is not a guarantee for every speaker. Do Not Disturb and provider permissions may affect announcements.

![Sample speaker grid with playing, grouped, paused and offline states](screenshots/guide-speakers-dark.png)

## Navigate rooms

Rooms uses Home Assistant's room and floor assignments. The overview groups rooms by floor. The interactive view lets you select a floor and room, inspect its devices, and open the same device detail controls. It is a registry-based layout, not a measured 3D floor plan. Use **3D map** for a scanned home.

<table>
  <tr>
    <td valign="top" width="50%">
      <h3>Overview</h3>
      <img src="screenshots/guide-rooms-overview-dark.png" width="360" alt="Synthetic rooms grouped by ground and first floor">
    </td>
    <td valign="top" width="50%">
      <h3>Interactive</h3>
      <img src="screenshots/guide-rooms-interactive-dark.png" width="360" alt="Synthetic room selection with a Kitchen speaker below">
    </td>
  </tr>
</table>

## Arrange a map

The demo map uses simulated energy readings. Import a scan only when you are ready to use a private home layout. Drag a device to the floor or a wall; the sidebar keeps the device available and indicates placement. Read the [map guide](3d-map.md) for supported formats and navigation.

![Generated demo scene with transparent walls and illustrative devices](screenshots/map-layout-dark.png)

## Tune navigation and notifications

In **Settings → Navigation**, choose glass opacity. Floating headings share that preference. macOS Reduce Transparency and Increase Contrast override translucency for legibility. Activity filters select what appears in the timeline; notification preferences control which events can alert you. They are separate choices.

## Ask for help

Use **Settings → Help & Support** to prepare a draft. Review its text before opening your mail app, or copy it into webmail for `contact@elvisobi.com`. Hearth does not send it automatically. Do not include tokens, private camera pictures, exact household addresses or unredacted logs. [Support guide](../README.md#8-get-help-or-report-a-problem) and [security reporting](../SECURITY.md) have separate routes.

All images in this guide are generated from isolated sample data; see the [image register](screenshots/README.md) for limitations.
