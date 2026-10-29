#!/usr/bin/env python3
"""Import NHSE's bundled inventory icons and item-ID mapping; no network access.

Usage: python3 scripts/import-nhse-item-icons.py /path/to/NHSE
Upstream code/data provenance is recorded in THIRD-PARTY-NOTICES.md.
"""
from pathlib import Path
import json
import re
import shutil
import struct
import sys


def generate(upstream):
    root = Path(__file__).resolve().parent.parent
    resources = root / "Sources/ACNHMac/Resources"
    menu = upstream / "NHSE.Sprites/Resources/MenuIcon"
    enum = (upstream / "NHSE.Core/Structures/Item/ItemMenuIconType.cs").read_text(encoding="utf-8-sig")
    names = {}
    ordinal = 0
    for name, explicit in re.findall(r"^\s*(\w+)(?:\s*=\s*([^,]+))?,\s*$", enum, re.MULTILINE):
        if explicit:
            ordinal = 65535 if explicit == "ushort.MaxValue" else int(explicit, 0)
        names[ordinal] = name
        ordinal += 1
    data = (upstream / "NHSE.Core/Resources/byte/item_menuicon.bin").read_bytes()
    assert len(data) % 2 == 0
    menu_ids = list(struct.unpack("<" + "H" * (len(data) // 2), data))
    images = {p.stem: p for p in menu.glob("*.png")}
    fallback = upstream / "NHSE.Sprites/Resources/Misc/leaf.png"
    assert fallback.is_file()
    files = {"item-icon-leaf": fallback}
    mapping = {}
    for item_id, icon_id in enumerate(menu_ids):
        name = names.get(icon_id)
        if name == "Leaf":
            name = "Leaf1"  # Same distinction as NHSE ItemSprite.TryGetMenuIconSprite.
        image = images.get(name)
        key = "item-icon-" + image.stem if image else "item-icon-leaf"
        if image:
            files[key] = image
        mapping[str(item_id)] = key
    # NHSE maps placed flowers/trees/etc. to their held item before resolving an icon.
    item_count = len((resources / "items.txt").read_text().splitlines())
    fields = (upstream / "NHSE.Core/Structures/Item/FieldItem/FieldItemList.cs").read_text(encoding="utf-8-sig")
    for item_id, dig, pick in re.findall(r"new FieldItemDefinition\(\s*(\d+),\s*(\d+)\s*,\s*(\d+)", fields):
        item_id, dig, pick = int(item_id), int(dig), int(pick)
        held = pick if pick != 65534 else dig if dig != 65534 else item_id
        if item_id >= item_count and held < item_count:
            mapping[str(item_id)] = mapping.get(str(held), "item-icon-leaf")
    for key, path in files.items():
        content = path.read_bytes()
        assert content[:8] == b"\x89PNG\r\n\x1a\n", path
        assert all(v > 0 for v in struct.unpack_from(">II", content, 16)), path
        shutil.copy2(path, resources / (key + ".png"))
    (resources / "item-icons.json").write_text(json.dumps(mapping, separators=(",", ":"), sort_keys=True) + "\n")
    for key in set(mapping.values()):
        assert (resources / (key + ".png")).is_file(), key
    print(f"Imported {len(files)} inventory icons; {len(mapping)} item-ID mappings")
    for item_id in [0x9C9, 0x9C5]:
        print(hex(item_id), mapping.get(str(item_id)))


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit(__doc__)
    generate(Path(sys.argv[1]))
