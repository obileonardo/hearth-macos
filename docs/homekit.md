# HomeKit, Apple Home and Hearth

Hearth uses the devices exposed by your Home Assistant server. It does not currently connect directly to an Apple Home household or replace its controller. Choose the route that matches your goal.

| Goal | Integration | Direction |
|---|---|---|
| Use a compatible HomeKit accessory in Hearth | **HomeKit Device** in Home Assistant | Accessory → Home Assistant → Hearth |
| Use Home Assistant entities in Apple's Home app or Siri | **HomeKit Bridge** in Home Assistant | Home Assistant → Apple Home |
| Import an Apple Home household directly into Hearth | Not implemented | No direct native HomeKit setup is claimed |

## Find the right integration

![Synthetic integration search showing HomeKit Bridge and HomeKit Device](screenshots/guide-integration-add-dark.png)

This is Hearth’s real integration search view rendered with an offline sample catalog. It demonstrates where to look; it contains no pairing code, Apple account or connected accessory.

## A. Bring a HomeKit accessory into Hearth

For a new, unpaired Ethernet/Wi-Fi accessory:

1. Confirm compatibility and locate its pairing code. Keep that code private.
2. Power it on and connect it to the same network as Home Assistant.
3. In Home Assistant, open **Settings → Devices & services**. Select **Configure** on the discovered **HomeKit Device** entry.
4. Enter its pairing code, assign a room and finish. Check the created entities in Home Assistant.
5. In Hearth, open **Rooms → that room**, or the matching Climate/Assets page, to see supported controls.

Already paired to Apple Home? Pause before migrating it. A HomeKit accessory can be paired to one controller at a time; changing the controller can affect an existing setup. Review the manufacturer's procedure and Home Assistant's guidance, then choose a recovery plan. This guide does not ask you to reset or unpair a working accessory.

Bluetooth and Thread need their own prerequisites; follow the appropriate sections of the [official HomeKit Device guide](https://www.home-assistant.io/integrations/homekit_controller/). A paired accessory may still expose no usable entities if its type is unsupported.

## B. Show Home Assistant devices in Apple Home

1. In Home Assistant, open **Settings → Devices & services → Add integration → HomeKit Bridge**.
2. Follow the setup and choose the supported entities to expose. Start with the devices you actually want in Apple Home.
3. Find the bridge's pairing QR/PIN in Home Assistant, including its notification area if necessary. Keep it private.
4. In Apple's Home app, choose **Add Accessory** and scan that QR code, or select the bridge and enter its code. Review any accessory confirmation and finish the Apple Home setup.
5. Check the selected accessories in Apple Home. Hearth continues using its existing Home Assistant connection.

Supported types, filtering and network discovery determine the result. Docker isolation and network segmentation can require additional configuration; review it before changing bindings or firewall rules. See the [official HomeKit Bridge guide](https://www.home-assistant.io/integrations/homekit/) for current pairing, limitations and troubleshooting.

## Where Hearth's integration manager fits

Open **Hearth Settings → Signed in as… → Integrations and devices** to review installed entries or search **Add integration**. Hearth handles supported forms and browser handoffs from your server. For HomeKit discovery, QR codes or a step Hearth cannot render, continue in Home Assistant's own interface. There is no simulated pairing success in the app.

Apple TV/HomePod speaker playback uses Home Assistant's separate [Apple TV integration](https://www.home-assistant.io/integrations/apple_tv/); it is not the same as HomeKit Device or HomeKit Bridge. Use your model's supported setup and keep existing Home permissions unchanged until you have reviewed the requirements.

## After setup

Assign devices to rooms in Home Assistant, then use Hearth's Rooms overview or interactive room selector. The example below is generated from synthetic rooms and speakers; it does not show a real Apple Home account or demonstrate HomeKit pairing.

![Synthetic Rooms overview with devices assigned to ground and first floors](screenshots/guide-rooms-overview-dark.png)

If an accessory appears in Home Assistant but not where expected in Hearth, check its entity types, availability and room assignment. Do not delete an integration or reset a device solely to refresh the UI. For help, prepare a reviewed draft through **Settings → Help & Support** without including pairing codes or credentials.

Official integration instructions reviewed 2026-10-16. Actual models, firmware, Home Assistant versions and network arrangements still need local validation.
