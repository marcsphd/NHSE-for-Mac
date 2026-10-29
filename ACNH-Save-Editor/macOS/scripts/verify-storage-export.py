#!/usr/bin/env python3
"""Independently verify storage edits with Python/OpenSSL, without ACNHCore.

Usage: python3 scripts/verify-storage-export.py ORIGINAL EXPORTED EXPECTED.json
JSON maps one-based storage slot numbers to complete eight-byte item records.
Example: {"80": "9125000000000000"} expects one golden axe in slot 80.
Use {} to check a no-op. Both folders are read only.
"""
import importlib.util
import json
import pathlib
import struct
import sys

spec = importlib.util.spec_from_file_location("settings_crypto", pathlib.Path(__file__).with_name("verify-settings-export.py"))
helper = importlib.util.module_from_spec(spec)
spec.loader.exec_module(helper)


def verify(original, exported, edits):
    path = pathlib.Path("Villager0/personal.dat")
    files = {p.relative_to(original) for p in original.rglob("*") if p.is_file()}
    assert files == {p.relative_to(exported) for p in exported.rglob("*") if p.is_file()}, "File inventories differ"
    for other in files - {path}:
        assert (original / other).read_bytes() == (exported / other).read_bytes(), f"Unexpected change: {other}"
    before, after = helper.decrypt(original, path), helper.decrypt(exported, path)
    capacity = struct.unpack_from("<I", before, 0x496AC)[0]
    assert capacity <= 9_000, "Invalid source storage capacity"
    expected = bytearray(before)
    for key, hex_item in edits.items():
        index = int(key) - 1
        assert 0 <= index < capacity, f"Storage slot {key} is locked or out of range"
        raw = bytes.fromhex(hex_item)
        assert len(raw) == 8, "Expected eight-byte item records"
        offset = 0x37D6C + index * 8
        expected[offset:offset + 8] = raw
    for offset, length in [(0x110, 0x37ACC), (0x37BE0, 0x3CE5C)]:
        assert struct.unpack_from("<I", before, offset)[0] == helper.crypto.murmur(before[offset + 4:offset + 4 + length]), "Invalid source hash"
        checksum = helper.crypto.murmur(after[offset + 4:offset + 4 + length])
        assert struct.unpack_from("<I", after, offset)[0] == checksum, "Invalid export hash"
        struct.pack_into("<I", expected, offset, checksum)
    assert expected == after, "Unrequested storage data, capacity, or unrelated bytes changed"
    print(f"PASS: {capacity} unlocked storage slots; {len(edits)} requested edits; both personal checksums verified")
    print("PASS: locked storage, capacity, pockets, unrelated bytes, headers, and sibling files preserved")


if __name__ == "__main__":
    verify(pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2]), json.loads(pathlib.Path(sys.argv[3]).read_text()))
