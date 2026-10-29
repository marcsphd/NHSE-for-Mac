#!/usr/bin/env python3
"""Independently check settings exports with Python/OpenSSL, without ACNHCore.

Usage: python3 scripts/verify-settings-export.py ORIGINAL EXPORTED EXPECTED.json
JSON keys: playerName, islandName, birthMonth, birthDay, hemisphere, airportColor,
weatherSeed, tourHemisphere, tourWeatherSeed, nativeFruit, sisterFruit,
nativeFlower, sisterFlower. Omitted fields must remain unchanged. {} checks a no-op.
Neither save folder is modified.
"""
import importlib.util
import json
import pathlib
import struct
import subprocess
import sys

spec = importlib.util.spec_from_file_location("crypto", pathlib.Path(__file__).with_name("verify-map-ui-export.py"))
crypto = importlib.util.module_from_spec(spec)
spec.loader.exec_module(crypto)

MAIN_REGIONS = [(0x110, 0x1E339C), (0x1E34B0, 0x3D089C)]
for base in [0x5B3E60, 0x6288A0, 0x69D2E0, 0x711D20, 0x786760, 0x7FB1A0, 0x86FBE0, 0x8E4620]:
    MAIN_REGIONS += [(base, 0x37ACC), (base + 0x37AD0, 0x3CE5C)]
MAIN_REGIONS.append((0x958F50, 0x57F3C))
REGIONS = {
    "main.dat": MAIN_REGIONS,
    "personal.dat": [(0x110, 0x37ACC), (0x37BE0, 0x3CE5C)],
    "postbox.dat": [(0x100, 0x4732C)],
    "photo_studio_island.dat": [(0x100, 0x2F54C)],
    "profile.dat": [(0x100, 0x6945C)],
    "wherearen.dat": [(0x100, 0xB8A3DC)],
}


def decrypt(folder, path):
    header = (folder / path.parent / (path.stem + "Header.dat")).read_bytes()
    return subprocess.run(["openssl", "enc", "-aes-128-ctr", "-K", crypto.parameter(header, 0).hex(),
                           "-iv", crypto.parameter(header, 2).hex(), "-nopad", "-nosalt"],
                          input=(folder / path).read_bytes(), capture_output=True, check=True).stdout


def name_bytes(name):
    encoded = name.encode("utf-16le")
    assert 0 < len(encoded) <= 20 and "\0" not in name
    return encoded.ljust(20, b"\0")


def verify(original, exported, edits):
    known = {"playerName", "islandName", "birthMonth", "birthDay", "hemisphere", "airportColor", "weatherSeed",
             "tourHemisphere", "tourWeatherSeed", "nativeFruit", "sisterFruit", "nativeFlower", "sisterFlower"}
    assert edits.keys() <= known, "Unknown expected setting"
    paths = {p.relative_to(original) for p in original.rglob("*") if p.is_file()}
    assert paths == {p.relative_to(exported) for p in exported.rglob("*") if p.is_file()}, "File inventories differ"
    personal = decrypt(original, pathlib.Path("Villager0/personal.dat"))
    identities = []
    for key, offset in [("playerName", 0xC264), ("islandName", 0xC248)]:
        if key in edits:
            old = personal[offset:offset + 24]
            assert struct.unpack_from("<I", old)[0] != 0
            identities.append((old, old[:4] + name_bytes(edits[key])))
    changed = 0
    for path in sorted(paths):
        a, b = (original / path).read_bytes(), (exported / path).read_bytes()
        if path.name not in REGIONS or (path.name != "main.dat" and path.parent.name not in {f"Villager{i}" for i in range(8)}):
            assert a == b, f"Unexpected change: {path}"
            continue
        before, after = decrypt(original, path), decrypt(exported, path)
        expected = bytearray(before)
        if str(path) == "Villager0/personal.dat":
            for key, offsets in [("birthMonth", [0x1352C, 0x36598]), ("birthDay", [0x1352D, 0x36599])]:
                if key in edits:
                    for offset in offsets:
                        expected[offset] = edits[key]
            if "nativeFruit" in edits and edits["nativeFruit"] != struct.unpack_from("<H", decrypt(original, pathlib.Path("main.dat")), 0x495170)[0]:
                struct.pack_into("<H", expected, 0x3659C, edits["nativeFruit"])
        if str(path) == "main.dat":
            fields = [("hemisphere", 0x1E3714, "B"), ("airportColor", 0x575DC0, "B"),
                      ("weatherSeed", 0x1E3718, "I"), ("tourHemisphere", 0x97D470, "B"),
                      ("tourWeatherSeed", 0x97D474, "I"), ("nativeFruit", 0x495170, "H"),
                      ("sisterFruit", 0x495172, "H"), ("nativeFlower", 0x495195, "B"), ("sisterFlower", 0x495194, "B")]
            for key, offset, fmt in fields:
                if key in edits:
                    struct.pack_into("<" + fmt, expected, offset, edits[key])
            if "nativeFruit" in edits and edits["nativeFruit"] != struct.unpack_from("<H", before, 0x495170)[0]:
                expected[0x22EDF6:0x22EDFB] = bytes(int(value == edits["nativeFruit"]) for value in [2213, 2214, 2285, 2286, 2287])
        for old, new in identities:
            expected = expected.replace(old, new)
        for offset, length in REGIONS[path.name]:
            assert struct.unpack_from("<I", before, offset)[0] == crypto.murmur(before[offset + 4:offset + 4 + length]), f"Bad source hash: {path}"
            checksum = crypto.murmur(after[offset + 4:offset + 4 + length])
            assert struct.unpack_from("<I", after, offset)[0] == checksum, f"Bad export hash: {path}"
            struct.pack_into("<I", expected, offset, checksum)
        assert expected == after, f"Unexpected decrypted bytes: {path}"
        changed += a != b
    print(f"PASS: {len(edits)} requested settings; {changed} changed save files; identity references and checksums verified")
    print("PASS: all unrelated decrypted bytes, headers, and other files preserved")


if __name__ == "__main__":
    verify(pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2]), json.loads(pathlib.Path(sys.argv[3]).read_text()))
