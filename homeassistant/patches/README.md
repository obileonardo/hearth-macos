# Home Assistant patches

Small, optional fixes for problems in community libraries that Home Assistant uses,
checked against the files inside an optional Home Assistant/bridge container. The
Hearth application build never runs these scripts. An upstream update can replace
patched files or change their shape; re-check rather than assuming compatibility.

## Safe workflow and compatibility

All four patches **check without writing by default**. Only `--apply` writes module
files. Python patches also require `patch_safety.py` beside the script; copy both.
Use `--root /path/to/integration-or-package` to check an offline Python fixture or
reviewed copy without importing the installed integration. The Eufy script accepts
its build directory as the first positional argument.

1. Record the installed upstream package/image version and image digest privately.
   Do not assume a broad version family establishes compatibility.
2. Arrange an owner-approved backup/image rollback of the affected module files and
   persistent volumes. These scripts do not copy credentials, pairings or databases.
3. Run the default check; inspect the expected changes in a disposable copy first.
   Unknown, duplicate or incomplete anchors fail before any planned writes.
4. Obtain operational approval, then pass `--apply`. A successful check is not
   approval to restart a service or control a device.
5. Restart only the intended service after approval and verify its normal status.
   On failure, restore the approved original module/image without resetting volumes,
   accounts or device pairings.

Each file is replaced atomically. A caught write failure attempts to restore earlier
writes, provided those files have not changed concurrently. Multiple file replacements
are **not power-loss atomic**; keep the rollback plan even when preflight succeeds.
The scripts do not restart containers, switch image versions or alter network access.

| Patch | Documented target shape | Compatibility evidence |
| --- | --- | --- |
| Amazon | `aioamazondevices` 16.3.x sign-in snippets | Synthetic matching/changed/partial layouts; exact installed version and upstream revision not verified by this suite |
| Apple TV | Home Assistant `config_flow.py` and `__init__.py` scan snippets | Synthetic two-file preflight/idempotence/write-failure fixtures; no universal HA version claim |
| LG | Home Assistant `lg_thinq/switch.py` command/decorator snippets | Synthetic helper/replacement checks; exact installed HA revision requires local review |
| Eufy | `eufy-security-client` 4.1.x parser/metadata snippets | Synthetic two-file check/apply/idempotence; no camera-pairing or protocol verification |

Run the offline regression suite from the repository root:

```sh
python3 -m unittest discover -s Tests/MaintenancePatches -v
```

It uses only temporary synthetic files. Node is required for the Eufy fixture; that
case is explicitly skipped if Node is unavailable. It never imports Home Assistant,
connects to a service, applies a patch to an installed package or restarts a container.

## `amazon_two_page_signin.py`

**Symptom:** the Alexa Devices integration says *Invalid authentication* even with the
right email, password and authenticator code.

**Cause:** Amazon's sign-in now asks for the email on one page and the password on the
next. `aioamazondevices` 16.3.x sends both to the first page, lands on the password page,
finds no code box and gives up before your code is used.

**Fix:** submit the password on the second page. If it still fails, the patch logs which
page Amazon stopped on (title, alert text, field metadata and form actions). Those diagnostics may contain personal information. Review and redact them before sharing; avoid attaching account details or authentication material.

```sh
docker cp patch_safety.py homeassistant:/tmp/
docker cp amazon_two_page_signin.py homeassistant:/tmp/
docker exec homeassistant python3 /tmp/amazon_two_page_signin.py
# After reviewing the check and obtaining approval:
docker exec homeassistant python3 /tmp/amazon_two_page_signin.py --apply
# Restart only after separate operational approval.
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
docker cp patch_safety.py homeassistant:/tmp/
docker cp lg_switch_case.py homeassistant:/tmp/
docker exec homeassistant python3 /tmp/lg_switch_case.py
# After reviewing the check and obtaining approval:
docker exec homeassistant python3 /tmp/lg_switch_case.py --apply
# Restart only after separate operational approval.
```

## `apple_tv_unicast.py`

**Symptom:** with Home Assistant in Docker (for example Colima on a Mac), adding an Apple
TV or HomePod by IP address says *No devices found*, even though it's on and reachable.

**Cause:** given an address, the integration still asks the device about itself through
Home Assistant's zeroconf (mDNS) service, and Docker's network translation drops the
answers.

**Fix:** when the address is known, use pyatv's own unicast lookup, which gets through.

```sh
docker cp patch_safety.py homeassistant:/tmp/
docker cp apple_tv_unicast.py homeassistant:/tmp/
docker exec homeassistant python3 /tmp/apple_tv_unicast.py
# After reviewing the check and obtaining approval:
docker exec homeassistant python3 /tmp/apple_tv_unicast.py --apply
# Restart only after separate operational approval.
```

AirPlay access is a separate owner policy. Some existing setups use **Home app → Home Settings → Speakers & TV → Allow Access → Anyone on the Same Network** without a password. That permits other clients on that network to connect; it is not a required Hearth setting or an automatic step in this patch. Keep your current access policy unless you deliberately choose that tradeoff. If your required authentication policy is unsupported by the installed integration, leave it enabled and treat that AirPlay path as unavailable rather than weakening it for setup.

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
# After reviewing the check and obtaining approval:
docker exec eufy-security-ws node /tmp/eufy_identity_person_name.js --apply
# Restart only after separate operational approval.
```

Re-check after updating the eufy-security-ws image. Preserve its persistent volume
and settings during any approved restart/rollback; these scripts do not manage them.
