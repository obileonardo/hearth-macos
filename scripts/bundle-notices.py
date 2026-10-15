#!/usr/bin/env python3
"""Copy or verify the exact source notices in a staged app; never change source."""
import argparse
from pathlib import Path
import shutil
import sys

ROOT = Path(__file__).resolve().parent.parent
NOTICE_PATHS = (
    "LICENSE",
    "THIRD_PARTY_NOTICES.md",
    "docs/licenses/Apache-2.0.txt",
    "docs/licenses/eufy-security-client-MIT.txt",
)


def notices(app, verify=False, source_root=ROOT):
    app = Path(app).absolute()
    resources = app / "Contents" / "Resources"
    for relative in NOTICE_PATHS:
        source = source_root / relative
        target = resources / relative
        if source.is_symlink() or not source.is_file():
            raise ValueError(f"Missing regular source notice: {relative}")
        # No links in the destination chain: copies must stay inside the bundle.
        if any(p.is_symlink() for p in (target, *target.parents) if p == app or app in p.parents):
            raise ValueError(f"Symlink in staged notice path: {relative}")
        if verify:
            if not target.is_file() or target.read_bytes() != source.read_bytes():
                raise ValueError(f"Bundled notice differs from source: {relative}")
        else:
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(source, target)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path)
    parser.add_argument("--verify", action="store_true")
    args = parser.parse_args()
    try:
        notices(args.app, verify=args.verify)
    except (OSError, ValueError) as error:
        print(f"Notice check stopped: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
