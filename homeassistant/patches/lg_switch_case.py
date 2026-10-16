"""Make LG ThinQ switches like the AC's Display light actually switch.

Home Assistant's lg_thinq integration sends "on"/"off" for some switches (display light,
air clean, UV nano), but devices whose LG profile lists "ON"/"OFF" reject the lowercase
value with "Fail device control", so the switch never moves. This retries a refused
command with the value in upper case.

Check first with the read-only default; use --apply only after approval.
Copy patch_safety.py beside this script. See README.md for preflight, compatibility
limitations and an approved container rollback/restart procedure.

"""

from patch_safety import arguments, commit, replace_once

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


def plan(folder):
    path = folder / "switch.py"
    source = path.read_text()
    if marker in source and (helper.lstrip("\n") not in source or any(new not in source for _, new in replacements)):
        raise ValueError("switch.py: partial LG patch; nothing applied")
    updated = source
    for old, new in replacements:
        updated = replace_once(updated, old, new, "LG switch command")
    anchor = "    @override\n    async def async_turn_on(self, **kwargs: Any) -> None:"
    updated = replace_once(updated, anchor, helper.lstrip("\n") + "\n" + anchor, "LG switch helper")
    return [(path, source, updated)]


def main():
    args = arguments("Check/apply the optional LG switch case maintenance patch")
    if args.root is None:
        import homeassistant.components.lg_thinq as lg
        from pathlib import Path
        args.root = Path(lg.__file__).parent
    commit(plan(args.root), args.apply)


if __name__ == "__main__":
    main()
