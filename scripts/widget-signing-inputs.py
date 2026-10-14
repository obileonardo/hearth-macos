#!/usr/bin/env python3
"""Validate supplied macOS profiles and produce only the required entitlements.

No certificates or profiles are requested, created, uploaded, or printed.
"""
from datetime import datetime, timezone
from pathlib import Path
import fnmatch
import plistlib
import sys


def validate_profile(path: Path, bundle: str, group: str):
    with path.open('rb') as handle:
        profile = plistlib.load(handle)
    if not set(profile.get('Platform', [])).intersection({'OSX', 'macOS'}):
        raise ValueError('A macOS provisioning profile is required')
    expiry = profile.get('ExpirationDate')
    if not isinstance(expiry, datetime) or expiry.replace(tzinfo=timezone.utc) <= datetime.now(timezone.utc):
        raise ValueError('The provisioning profile is expired or has no expiration')
    teams = profile.get('TeamIdentifier', [])
    prefixes = profile.get('ApplicationIdentifierPrefix', [])
    if len(teams) != 1 or len(prefixes) != 1:
        raise ValueError('The provisioning profile needs one team and application prefix')
    entitlements = profile.get('Entitlements', {})
    application = f'{prefixes[0]}.{bundle}'
    allowed = entitlements.get('com.apple.application-identifier', entitlements.get('application-identifier', ''))
    if not allowed or not fnmatch.fnmatchcase(application, allowed):
        raise ValueError('The provisioning profile does not authorize the bundle identifier')
    groups = entitlements.get('com.apple.security.application-groups', [])
    # Apple supports team-prefixed macOS groups without restricted group profiles.
    if not group.startswith(f'{teams[0]}.') and not any(fnmatch.fnmatchcase(group, item) for item in groups):
        raise ValueError('The provisioning profile does not authorize the selected app group')
    return teams[0], application


def generate(stage: Path, group: str):
    extension_team, extension_id = validate_profile(stage / 'extension-profile.plist', 'com.elvisobi.hearth.widgets', group)
    host_team, host_id = validate_profile(stage / 'host-profile.plist', 'com.elvisobi.hearth', group)
    if extension_team != host_team:
        raise ValueError('The app and extension profiles must belong to the same team')
    for name, application, sandbox in [('extension', extension_id, True), ('host', host_id, False)]:
        entitlements = {
            'com.apple.application-identifier': application,
            'com.apple.developer.team-identifier': host_team,
            'com.apple.security.application-groups': [group],
        }
        if sandbox:
            entitlements['com.apple.security.app-sandbox'] = True
        with (stage / f'{name}.entitlements').open('wb') as handle:
            plistlib.dump(entitlements, handle)


if __name__ == '__main__':
    try:
        generate(Path(sys.argv[1]), sys.argv[2])
    except (ValueError, OSError, KeyError, IndexError, plistlib.InvalidFileException) as error:
        raise SystemExit(f'Widget signing inputs rejected: {error}')
