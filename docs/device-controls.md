# Speaker and camera controls

Hearth targets the selected Home Assistant entity or device. It does not change a device to “playing” or “on” merely because a request was sent.

## Speakers

- Playing and paused speakers use the transport actions reported in `supported_features`. Where a speaker only supports Stop, its primary key uses Stop.
- An idle speaker needs new media; `media_play` only resumes an existing queue. For devices identified by the Home Assistant device registry as `alexa_devices`, the registered `alexa_devices.send_text_command` action receives `play music` and that device’s ID. Alexa uses the provider linked to its account.
- Choose music opens an explicit song/artist/station request for Alexa. Other integrations use a media identifier and media type/provider supported by that integration. Available input sources remain selectable.
- The grid, list and device detail share the same transport policy. Track and volume failures are displayed, and successful requests wait for the normal Home Assistant state feed to show playback.
- Announcements use the actual `notify.send_message` action and selected notify entity. A notify entity with `unknown` state can still be available: its state is the time of its last notification, so a never-used entity starts without a timestamp. Failed messages remain in the editor; accepted requests clear only the submitted draft.
- An active Do Not Disturb setting is shown beside the announcement editor. It is not silently disabled by Hearth, and an accepted request is not a promise that an announcement was audible.

## Cameras and other device settings

- Power commands preserve the entity’s actual domain. Switches, sliders and selectors wait for the authoritative Home Assistant state instead of pretending the change completed.
- Home Assistant rejects an action: the control shows the error. A power request with no resulting state after 15 seconds shows an unconfirmed-state explanation. Service responses have a 30-second acknowledgement limit; a timeout is not proof that the device never executed the request, so check it before retrying.
- Cameras on an Eufy HomeBase Professional (`T9000`) retain their Camera setting with an explicit unavailable-control explanation. The existing integration cannot deliver commands to that hub. Changing the UI or sending `switch.turn_on` again cannot repair an unsupported upstream hub protocol; other supported cameras keep their controls.
- Unavailable entities are disabled. Button and notify entities with no previous-use timestamp remain usable.

## Verification boundary

Automated fixtures test exact targets, idle versus paused routing, actual Alexa integration identification, capability masks, first-use announcements, service acknowledgement and rejected requests. They never connect to Home Assistant or send commands to real devices. The local action-helper checks compile the production source and use fixtures. Physical audio, camera privacy state and provider subscriptions must still be checked on supported connected hardware.

Protocol references: [Alexa Devices](https://www.home-assistant.io/integrations/alexa_devices/), [Alexa text commands](https://www.home-assistant.io/actions/alexa_devices.send_text_command/), [notify entities](https://developers.home-assistant.io/docs/core/entity/notify/), [media-player capabilities](https://developers.home-assistant.io/docs/core/entity/media-player/).
