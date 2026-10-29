#!/usr/bin/env python3
"""Independently verify an unchanged export or a single building-position edit.

Usage: python3 scripts/verify-building-export.py ORIGINAL EXPORTED
       python3 scripts/verify-building-export.py ORIGINAL EXPORTED --slot 4 --x 126 --y 118 --angle 0
Slot numbers are one-based. Coordinates are the raw half-tile values shown in the app.
Reads save data locally; neither folder is modified.
"""
import argparse
import importlib.util
import pathlib
import struct

spec = importlib.util.spec_from_file_location("fixture_crypto", pathlib.Path(__file__).with_name("verify-map-ui-export.py"))
crypto = importlib.util.module_from_spec(spec)
spec.loader.exec_module(crypto)


def verify(original, exported, slot=None, x=None, y=None, angle=None):
    source_files = {str(p.relative_to(original)): p for p in original.rglob("*") if p.is_file()}
    output_files = {str(p.relative_to(exported)): p for p in exported.rglob("*") if p.is_file()}
    assert source_files.keys() == output_files.keys(), "File inventories differ"
    for name, path in source_files.items():
        if slot is None or name != "main.dat":
            assert path.read_bytes() == output_files[name].read_bytes(), name
    if slot is None:
        print("PASS: unchanged export is byte-identical for every save file")
        return
    before, after = crypto.decrypt(original), crypto.decrypt(exported)
    assert len(before) == len(after) == 0x9B0E90
    expected = bytearray(before)
    offset = 0x32F700 + (slot - 1) * 20
    assert struct.unpack_from("<H", before, offset)[0] != 0, "Empty building slot"
    struct.pack_into("<HHB", expected, offset + 2, x, y, angle)
    regions = [(0x110, 0x1E339C), (0x1E34B0, 0x3D089C)]
    for base in [0x5B3E60, 0x6288A0, 0x69D2E0, 0x711D20,
                 0x786760, 0x7FB1A0, 0x86FBE0, 0x8E4620]:
        regions += [(base, 0x37ACC), (base + 0x37AD0, 0x3CE5C)]
    regions.append((0x958F50, 0x57F3C))
    for start, length in regions:
        checksum = crypto.murmur(after[start + 4:start + 4 + length])
        assert struct.unpack_from("<I", after, start)[0] == checksum, hex(start)
        struct.pack_into("<I", expected, start, checksum)
    assert expected == after, "Unexpected island bytes changed"
    print(f"PASS: building slot {slot} saved at ({x}, {y}), rotation {angle * 90}°")
    print("PASS: all 19 island checksums; all other island bytes and sibling files preserved")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("original", type=pathlib.Path)
    parser.add_argument("exported", type=pathlib.Path)
    parser.add_argument("--slot", type=int)
    parser.add_argument("--x", type=int)
    parser.add_argument("--y", type=int)
    parser.add_argument("--angle", type=int)
    args = parser.parse_args()
    values = [args.slot, args.x, args.y, args.angle]
    if any(v is not None for v in values):
        if any(v is None for v in values) or not (1 <= args.slot <= 46 and 0 <= args.x < 288 and 0 <= args.y < 256 and 0 <= args.angle < 4):
            parser.error("Specify --slot 1–46, --x 0–287, --y 0–255 and --angle 0–3 together")
    verify(args.original, args.exported, args.slot, args.x, args.y, args.angle)
