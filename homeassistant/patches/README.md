# Home Assistant patches

Small, optional fixes for problems in community libraries that Home Assistant uses,
applied inside the Home Assistant container. Re-run after updating Home Assistant,
because an update replaces the patched files.

## `amazon_two_page_signin.py`

**Symptom:** the Alexa Devices integration says *Invalid authentication* even with the
right email, password and authenticator code.

**Cause:** Amazon's sign-in now asks for the email on one page and the password on the
next. `aioamazondevices` 16.3.x sends both to the first page, lands on the password page,
finds no code box and gives up before your code is used.

**Fix:** submit the password on the second page. If it still fails, the patch logs which
page Amazon stopped on (title, alert text, field metadata and form actions). Those diagnostics may contain personal information. Review and redact them before sharing; avoid attaching account details or authentication material.

```sh
docker cp amazon_two_page_signin.py homeassistant:/tmp/
docker exec homeassistant python3 /tmp/amazon_two_page_signin.py
docker restart homeassistant
```

Also check you're signing in with the identity your Amazon account really uses. An
unverified email on the account gives *No account found*; use the mobile number instead.

## `lg_switch_case.py`

**Symptom:** on an LG ThinQ air conditioner, the **Display light** switch (and other
on/off settings) does nothing and Home Assistant logs a failed device control.

**Cause:** the LG ThinQ integration sends `"on"` and `"off"`. Some LG air conditioners only
accept `"ON"` and `"OFF"`.

**Fix:** send the value as given and, if LG rejects it, try again in capitals.

```sh
docker cp lg_switch_case.py homeassistant:/tmp/
docker exec homeassistant python3 /tmp/lg_switch_case.py
docker restart homeassistant
```

## `apple_tv_unicast.py`

**Symptom:** with Home Assistant in Docker (for example Colima on a Mac), adding an Apple
TV or HomePod by IP address says *No devices found*, even though it's on and reachable.

**Cause:** given an address, the integration still asks the device about itself through
Home Assistant's zeroconf (mDNS) service, and Docker's network translation drops the
answers.

**Fix:** when the address is known, use pyatv's own unicast lookup, which gets through.

```sh
docker cp apple_tv_unicast.py homeassistant:/tmp/
docker exec homeassistant python3 /tmp/apple_tv_unicast.py
docker restart homeassistant
```

Also set **Home app → Home Settings → Speakers & TV → Allow Access** to *Anyone on the
Same Network*, with no password. The integration can't use AirPlay's password.

## `eufy_identity_person_name.js`

**Symptom:** Eufy recognises a familiar face, but the camera's **Person name** sensor in
Home Assistant only ever says *Unknown Person* or *No Person*, and the eufy-security-ws
log shows `Invalid Property error ... propertyName: 'identityPersonDetected'`.

**Cause:** with cameras paired to a HomeBase the library doesn't treat as a HomeBase 3
(the HomeBase Professional, T9000, for one), eufy-security-client 4.1.x reads indoor and
solo camera pushes without the recognised person's name, so it always reports *Unknown*.
Those cameras also lack the *identity person* and *stranger* properties, so the push is
logged as an error.

**Fix:** copy the name (and the person's id) from the push, and give cameras paired to a
base the two missing properties. The Person name sensor then shows the name for the event
duration (10 seconds by default) before going back to *No Person*.

This one patches the eufy-security-ws bridge, not Home Assistant:

```sh
docker cp eufy_identity_person_name.js eufy-security-ws:/tmp/
docker exec eufy-security-ws node /tmp/eufy_identity_person_name.js
docker restart eufy-security-ws
```

Re-run after updating the eufy-security-ws image. The restart keeps the bridge's settings.
