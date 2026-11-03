"""Remove the [patch] entries that Cargo.lock records under [[patch.unused]].

The workspaces patch the whole egui family onto storytold's fork, including crates none of them
depend on (egui_demo_lib, ...). Cargo records those as [[patch.unused]] and still looks each one
up in the patch source, but rustPlatform.fetchCargoVendor only vendors locked packages, so the
offline build fails with "patch location ... does not contain packages matching". Unused patches
never affect resolution: dropping them from Cargo.toml and Cargo.lock together keeps `--locked`
builds identical.

Run from the workspace root after cargoSetupHook has validated Cargo.lock against the vendor dir.
"""

import re
import tomllib
from pathlib import Path

lock_path, manifest_path = Path("Cargo.lock"), Path("Cargo.toml")
lock = lock_path.read_text()
unused = {entry["name"] for entry in tomllib.loads(lock).get("patch", {}).get("unused", [])}

if unused:
    # Cargo.lock: drop every [[patch.unused]] table (header up to the next header).
    kept, skipping = [], False
    for line in lock.splitlines():
        if line.startswith("["):
            skipping = line == "[[patch.unused]]"
        if not skipping:
            kept.append(line)
    lock_path.write_text("\n".join(kept).rstrip("\n") + "\n")

    # Cargo.toml: drop `name = {...}` lines in [patch.<registry>] and [patch.<registry>.<name>] tables.
    kept, section, skipping = [], "", False
    for line in manifest_path.read_text().splitlines():
        header = re.match(r"^\s*\[([^\[\]]+)\]\s*(#.*)?$", line)
        if header:
            section = header.group(1).strip()
            parts = [p.strip().strip('"') for p in section.split(".")]
            skipping = parts[0] == "patch" and len(parts) == 3 and parts[2] in unused
        elif section.startswith("patch.") and not skipping:
            key = re.match(r'^\s*"?([A-Za-z0-9_-]+)"?\s*=', line)
            if key and key.group(1) in unused:
                continue
        if not skipping:
            kept.append(line)
    manifest_path.write_text("\n".join(kept) + "\n")

    print(f"dropped unused cargo patches: {', '.join(sorted(unused))}")
