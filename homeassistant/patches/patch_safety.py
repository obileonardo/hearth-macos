"""Offline preflight and explicit application for optional maintenance patches.

No upstream package is imported until the caller chooses its installed target.
This helper never restarts services and never creates a backup of private config.
"""
import argparse
import os
from pathlib import Path
import tempfile


def replace_once(source, old, new, label):
    if source.count(new) == 1:
        if old in source.replace(new, "", 1):
            raise ValueError(f"{label}: duplicate original anchor; nothing applied")
        return source
    if source.count(old) != 1:
        raise ValueError(f"{label}: unsupported or partially patched layout; nothing applied")
    return source.replace(old, new, 1)


def commit(plan, apply=False):
    """Validate the complete plan before writing. Restore originals on I/O failure.

    Each replacement is atomic, but a process/power failure across multiple files
    cannot be made globally atomic; keep an approved container/image rollback.
    """
    pending = [(Path(path), before, after) for path, before, after in plan if before != after]
    for path, before, _ in plan:
        if Path(path).read_text() != before:
            raise ValueError(f"{path.name}: changed since preflight; nothing applied")
    if not apply:
        for path, _, _ in pending:
            print(f"would patch: {path.name}")
        print(f"check complete: {len(pending)} file(s) need changes; use --apply explicitly")
        return
    written = []
    try:
        for path, before, after in pending:
            # Check again to avoid overwriting a concurrent package update.
            if path.read_text() != before:
                raise ValueError(f"{path.name}: changed since preflight")
            atomic_write(path, after)
            written.append((path, before, after))
    except BaseException:
        for path, before, after in reversed(written):
            if path.read_text() == after:
                atomic_write(path, before)
        raise
    print(f"applied: {len(written)} file(s); no service was restarted")


def atomic_write(path, source):
    if path.is_symlink() or not path.is_file():
        raise ValueError(f"{path.name}: expected a regular file")
    mode = path.stat().st_mode & 0o777
    descriptor, temporary = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        with os.fdopen(descriptor, "w") as stream:
            stream.write(source)
            stream.flush()
            os.fsync(stream.fileno())
        os.chmod(temporary, mode)
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def arguments(description):
    parser = argparse.ArgumentParser(description=description)
    parser.add_argument("--root", type=Path, help="explicit integration/package directory (offline fixture supported)")
    parser.add_argument("--apply", action="store_true", help="write only after all layout checks pass; default is read-only")
    return parser.parse_args()
