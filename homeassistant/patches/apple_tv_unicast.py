"""Let the Apple TV integration find HomePods and Apple TVs by address from Docker.

When you add an Apple TV or HomePod by IP address, Home Assistant asks the device about
itself through its own zeroconf (mDNS) service. Inside Docker behind NAT, as with Colima
on a Mac, the device's answers to that service never come back, so setup says "No
devices found" and a paired device never connects. pyatv's own unicast lookup does work
there. This makes the integration use it whenever it already knows the address.

Apply inside the Home Assistant container, then restart it:
    docker cp apple_tv_unicast.py homeassistant:/tmp/ && \\
    docker exec homeassistant python3 /tmp/apple_tv_unicast.py && docker restart homeassistant
Safe to run twice. Re-run after a Home Assistant update.
"""

import pathlib

import homeassistant.components.apple_tv as apple_tv

folder = pathlib.Path(apple_tv.__file__).parent
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

for name, (old, new) in edits.items():
    path = folder / name
    source = path.read_text()
    if marker in source:
        print(f"{name}: already patched")
    elif old in source:
        path.write_text(source.replace(old, new, 1))
        print(f"{name}: patched")
    else:
        raise SystemExit(f"{name}: the code has changed, so the patch wasn't applied")
