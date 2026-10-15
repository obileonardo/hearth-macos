# Air conditioner controls and troubleshooting

Hearth uses the modes advertised by each Home Assistant climate entity. It keeps the last
reported mode visible while a request is pending. An accepted service call is an
acknowledgement, not confirmation that the physical unit changed.

## If a mode fails to change

1. Check the physical unit or its manufacturer's app before repeating the action.
2. Confirm that the same mode works from the climate entity in Home Assistant. If it fails
   there too, the integration or device needs investigation.
3. In Hearth's error alert, choose **Copy diagnostic details**. Paste the summary into a
   support draft under **Settings → Help & Support** if you want to share it.

Copying is optional. The summary exists only in the open climate page and is copied only
when you press the button. Hearth does not automatically log, upload, attach or email it.
It contains the action, an allowlisted mode label, advertised standard modes, capability
validity, temperature step and a fixed error category. It excludes device names and IDs,
server addresses, credentials, actual room/target temperatures, timestamps and raw
provider error messages. Review anything else you add to a support message before sending.

The summary categorizes a vendor rejection separately from a connection error or a
request that was accepted but not subsequently reported. It does not claim to identify
the root cause inside the manufacturer's service.

## Recovery limits

For the specific `set_hvac_mode` rejection containing `Fail device control`, Hearth can
retry the exact request once. It reads fresh state, waits three seconds and reads again;
retrying requires the original mode to remain reported and the requested mode to remain
advertised. If the requested mode is already reported, it does not send again. A changed
mode/power state, unavailable device, missing refresh or cancellation prevents a retry.
Other errors and temperature requests do not retry automatically. No power cycle, target
temperature adjustment or integration/container changes are used as a workaround.

An intermittent LG/Home Assistant vendor rejection may therefore still surface. The
bounded recovery and diagnostic summary improve handling and investigation; they do not
promise that the vendor service can always accept a mode change.

## Temperature capabilities

The control preserves advertised positive fractional steps, including 0.1 and 0.25 degrees.
Dragging snaps relative to the advertised lower bound and remains within the advertised
range. Missing setpoints are not replaced with a made-up value. Nonfinite setpoints and
invalid/inverted bounds do not produce a slider or a temperature command. A fixed range
remains safe, and drawing is bounded even if an integration publishes an unusually broad
range. The rolling temperature animation continues to respect Reduce Motion.

## Validation

Fixture tests cover canonical mode payloads, advertised bounds and fractional steps,
missing/malformed numeric attributes, range snapping, same-device serialization,
cancellation, guarded single-retry behavior and report redaction. They send no commands
to real devices. End-to-end mode acceptance still needs the specific physical AC and
its integration; a passing fixture or Home Assistant acknowledgement cannot prove it.
