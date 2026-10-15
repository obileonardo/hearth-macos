#!/usr/bin/env python3
"""Stage and verify a source build before replacing a stopped Hearth installation."""
import argparse
from pathlib import Path
import os
import plistlib
import subprocess
import sys
import tempfile
import uuid


def validate_bundle(app):
    with (app / "Contents/Info.plist").open("rb") as stream:
        info = plistlib.load(stream)
    if info.get("CFBundleIdentifier") != "com.elvisobi.hearth":
        raise ValueError("Unexpected application identifier")
    executable = app / "Contents/MacOS/Hearth"
    if not executable.is_file() or executable.is_symlink() or not os.access(executable, os.X_OK):
        raise ValueError("Missing regular executable in staged Hearth.app")
    subprocess.run(["/usr/bin/codesign", "--verify", "--deep", "--strict", str(app)], check=True)


def copy_bundle(source, destination):
    subprocess.run(["/usr/bin/ditto", str(source), str(destination)], check=True)


def running_bundle(app):
    executable = str(app.resolve() / "Contents/MacOS/Hearth")
    processes = subprocess.run(
        ["/bin/ps", "-axo", "comm="], check=True, text=True, capture_output=True
    ).stdout.splitlines()
    return executable in (line.strip() for line in processes)


def install(source, destination, *, validate=validate_bundle, copy=copy_bundle, is_running=running_bundle):
    source, destination = Path(source).absolute(), Path(destination).absolute()
    if source.name != "Hearth.app" or destination.name != "Hearth.app":
        raise ValueError("Both app paths must end with Hearth.app")
    if destination.is_symlink():
        raise ValueError("Refusing to replace an installation symlink")
    source_real, target_real = source.resolve(), destination.resolve()
    if source_real == target_real or source_real in target_real.parents or target_real in source_real.parents:
        raise ValueError("Source and installation paths must be separate")
    if destination.exists() and not destination.is_dir():
        raise ValueError("Installation path is not an application directory")
    if is_running(destination):
        raise ValueError("Hearth is running at the destination. Quit it yourself before installing; no process was changed")
    validate(source)
    destination.parent.mkdir(parents=True, exist_ok=True)
    # Same-volume staging makes promotion a rename and preserves the old bundle.
    with tempfile.TemporaryDirectory(prefix=".hearth-install-", dir=destination.parent) as folder:
        staged = Path(folder) / "Hearth.app"
        copy(source, staged)
        validate(staged)
        # Recheck after a long copy; never deliberately replace a running app.
        if is_running(destination):
            raise ValueError("Hearth started during staging. Quit it yourself and retry; installation was unchanged")
        backup = None
        if destination.exists():
            backup = destination.parent / f".Hearth-before-install-{uuid.uuid4().hex}.app.backup"
            os.rename(destination, backup)
        try:
            os.rename(staged, destination)
        except OSError as promotion_error:
            if backup is not None:
                try:
                    os.rename(backup, destination)
                except OSError as rollback_error:
                    raise RuntimeError(
                        f"Promotion and automatic rollback failed; previous app is retained at {backup}. "
                        "Do not remove that backup; restore it to the destination before launching."
                    ) from rollback_error
            raise promotion_error
    return backup


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("destination", type=Path)
    args = parser.parse_args()
    try:
        backup = install(args.source, args.destination)
    except (OSError, ValueError, RuntimeError, plistlib.InvalidFileException, subprocess.CalledProcessError) as error:
        print(f"Installation stopped: {error}", file=sys.stderr)
        return 1
    print(f"Installed {args.destination}; no app was launched and no runtime settings were changed.")
    if backup is not None:
        print(f"Previous application retained: {backup}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
