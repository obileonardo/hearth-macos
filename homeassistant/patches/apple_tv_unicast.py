"""Let the Apple TV integration find HomePods and Apple TVs by address from Docker.

When you add an Apple TV or HomePod by IP address, Home Assistant asks the device about
itself through its own zeroconf (mDNS) service. Inside Docker behind NAT, as with Colima
on a Mac, the device's answers to that service never come back, so setup says "No
devices found" and a paired device never connects. pyatv's own unicast lookup does work
there. This makes the integration use it whenever it already knows the address.

Check first with the read-only default; use --apply only after approval.
Copy patch_safety.py beside this script. See README.md for preflight, compatibility
limitations and an approved container rollback/restart procedure.

"""

from patch_safety import arguments, commit, replace_once

marker = "# unicast scan patch"

edits = {
    "config_flow.py": (
        "    scan_result = await scan(loop, timeout=3, hosts=_host_filter(), aiozc=aiozc)\n",
        "    scan_result = await scan(  " + marker + "\n"
        "        loop, timeout=3, hosts=_host_filter(), aiozc=None if _host_filter() else aiozc\n"
        "    )\n",
    ),
    "__init__.py": (
        "            hosts=[address],\n            aiozc=aiozc,\n",
        "            hosts=[address],\n            aiozc=None,  " + marker + "\n",
    ),
}


def plan(folder):
    changes = []
    for name, (old, new) in edits.items():
        path = folder / name
        source = path.read_text()
        updated = replace_once(source, old, new, name)
        if marker in source and source != updated:
            raise ValueError(f"{name}: partial patch; nothing applied")
        changes.append((path, source, updated))
    return changes


def main():
    args = arguments("Check/apply the optional Apple TV unicast maintenance patch")
    if args.root is None:
        import homeassistant.components.apple_tv as apple_tv
        from pathlib import Path
        args.root = Path(apple_tv.__file__).parent
    commit(plan(args.root), args.apply)


if __name__ == "__main__":
    main()
