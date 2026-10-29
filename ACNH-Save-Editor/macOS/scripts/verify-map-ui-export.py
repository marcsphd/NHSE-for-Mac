#!/usr/bin/env python3
"""Verify the generated-fixture UI scenario documented in VALIDATION.md.

Usage: python3 scripts/verify-map-ui-export.py ORIGINAL_FIXTURE UI_EXPORT
Uses Python's format implementation and OpenSSL, independently of ACNHCore.
This is a test-fixture verifier, not a general save validator.
"""
import pathlib
import struct
import subprocess
import sys

MASK = 0xFFFFFFFF


def parameter(header, index):
    words = struct.unpack_from("<128I", header, 0x100)
    seed = words[words[index] & 127]
    state = []
    for i in range(1, 5):
        seed = (0x6C078965 * (seed ^ (seed >> 30)) + i) & MASK
        state.append(seed)

    def next_value():
        t = state[0]
        t = (t ^ (t << 11)) & MASK
        t ^= t >> 8
        value = t ^ state[3] ^ (state[3] >> 19)
        state[:] = state[1:] + [value]
        return value

    rolls = ((words[words[index + 1] & 127] & 127) & 15) + 1
    for _ in range(rolls * 2):
        next_value()
    return bytes(next_value() >> 24 for _ in range(16))


def decrypt(folder):
    header = (folder / "mainHeader.dat").read_bytes()
    return subprocess.run(
        ["openssl", "enc", "-aes-128-ctr", "-K", parameter(header, 0).hex(),
         "-iv", parameter(header, 2).hex(), "-nopad", "-nosalt"],
        input=(folder / "main.dat").read_bytes(), check=True, capture_output=True
    ).stdout


def rotate(value, amount):
    return ((value << amount) | (value >> (32 - amount))) & MASK


def murmur(data):
    result = 0
    for (word,) in struct.iter_unpack("<I", data):
        word = rotate((word * 0xCC9E2D51) & MASK, 15)
        result ^= (word * 0x1B873593) & MASK
        result = (rotate(result, 13) * 5 + 0xE6546B64) & MASK
    result ^= len(data)
    result ^= result >> 16
    result = (result * 0x85EBCA6B) & MASK
    result ^= result >> 13
    result = (result * 0xC2B2AE35) & MASK
    return result ^ (result >> 16)


def verify(original, exported):
    before, after = decrypt(original), decrypt(exported)
    assert len(before) == len(after) == 0x9B0E90
    expected = bytearray(before)
    water = {(x, y) for x in range(9, 12) for y in range(9, 12)}
    water |= {(x, y) for x in range(3) for y in range(3)}
    line = {(x, 20) for x in range(20, 31)}
    for x, y in water | line:
        struct.pack_into("<7H", expected, 0x30AB00 + (x * 96 + y) * 14,
                         0x15, 0, 0, 0x5C if (x, y) in line else 0, 0, 0, 0)
    struct.pack_into("<7H", expected, 0x30AB00 + (40 * 96 + 40) * 14,
                     0x29, 0, 1, 0x5C, 0, 0, 1)
    struct.pack_into("<HHB", expected, 0x32F702, 42, 62, 2)
    for layer, x, y in [(0, 112, 80), (1, 113, 81)]:
        for dx in range(2):
            for dy in range(2):
                index = layer * 55296 + (x + dx) * 192 + y + dy
                offset = 0x22F500 + index * 8
                if dx == dy == 0:
                    expected[offset:offset + 8] = struct.pack("<HBBHH", 0x9C9, 0x20, 0, 0, 0)
                else:
                    expected[offset:offset + 8] = struct.pack("<HHHBB", 0xFFFD, 0, 0x9C9, dx, dy)
                bit = (y + dy) * 288 + x + dx
                expected[0x307500 + layer * 0x1B00 + bit // 8] &= ~(1 << (bit % 8))
    regions = [(0x110, 0x1E339C), (0x1E34B0, 0x3D089C)]
    for base in [0x5B3E60, 0x6288A0, 0x69D2E0, 0x711D20,
                 0x786760, 0x7FB1A0, 0x86FBE0, 0x8E4620]:
        regions += [(base, 0x37ACC), (base + 0x37AD0, 0x3CE5C)]
    regions.append((0x958F50, 0x57F3C))
    for offset, length in regions:
        checksum = murmur(after[offset + 4:offset + 4 + length])
        assert struct.unpack_from("<I", after, offset)[0] == checksum, hex(offset)
        struct.pack_into("<I", expected, offset, checksum)
    if expected != after:
        differences = [i for i, (a, b) in enumerate(zip(expected, after)) if a != b]
        raise AssertionError(f"Unexpected bytes at {[hex(i) for i in differences[:20]]}")
    for path in original.rglob("*"):
        if path.is_file() and path.name != "main.dat":
            assert path.read_bytes() == (exported / path.relative_to(original)).read_bytes(), path.name
    print("PASS: exactly 30 terrain/path records, 8 item cells on two layers, one building.")
    print("PASS: all 19 island checksums; every unrelated byte and sibling file preserved.")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        raise SystemExit(__doc__)
    verify(pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2]))
