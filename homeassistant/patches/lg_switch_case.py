"""Make LG ThinQ switches like the AC's Display light actually switch.

Home Assistant's lg_thinq integration sends "on"/"off" for some switches (display light,
air clean, UV nano), but devices whose LG profile lists "ON"/"OFF" reject the lowercase
value with "Fail device control", so the switch never moves. This retries a refused
command with the value in upper case.

Apply inside the Home Assistant container, then restart it:
    docker cp lg_switch_case.py homeassistant:/tmp/ && \\
    docker exec homeassistant python3 /tmp/lg_switch_case.py && docker restart homeassistant
Safe to run twice. Re-run after a Home Assistant update.
"""

import pathlib

import homeassistant.components.lg_thinq as lg

path = pathlib.Path(lg.__file__).parent / "switch.py"
source = path.read_text()
marker = "# switch value case patch"

helper = '''

    ''' + marker + '''
    async def _post_value(self, value: str) -> None:
        """Post a value, retrying in upper case when the device's profile wants it."""
        try:
            await self.coordinator.api.post(self.property_id, value)
        except Exception:  # noqa: BLE001
            if value == value.upper():
                raise
            await self.coordinator.api.post(self.property_id, value.upper())
'''

replacements = [
    ("""            await self.async_call_api(
                self.coordinator.api.post(self.property_id, on_command)
            )""",
     """            await self.async_call_api(self._post_value(on_command))"""),
    ("""            await self.async_call_api(
                self.coordinator.api.post(self.property_id, off_command)
            )""",
     """            await self.async_call_api(self._post_value(off_command))"""),
]

if marker in source:
    print("already patched:", path)
else:
    for old, new in replacements:
        if old not in source:
            raise SystemExit(f"switch.py has changed shape, patch not applied: {path}")
        source = source.replace(old, new, 1)
    anchor = "    async def async_turn_on(self, **kwargs: Any) -> None:"
    if anchor not in source:
        raise SystemExit(f"switch.py has changed shape, patch not applied: {path}")
    source = source.replace("    @override\n" + anchor, helper.lstrip("\n") + "\n    @override\n" + anchor, 1)
    path.write_text(source)
    print("patched:", path)
