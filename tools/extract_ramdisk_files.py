#!/usr/bin/env python3
"""Extract files from a vendor_boot PLATFORM ramdisk.

The factory PLATFORM fragment carries everything the vendor ramdisk has to
provide, and the bootloader only uses that fragment when it boots Android
normally (the 0x2 RECOVERY fragment is only concatenated in recovery mode).
It is therefore repacked into our own, much smaller PLATFORM fragment:

    lib/modules             kernel modules plus the libmodprobe lists, loaded by
                            first stage init in both normal and recovery boot
    vendor/firmware         touch firmware, requested while the touch driver
                            probes, i.e. before /vendor is mounted
    first_stage_ramdisk     fstab.mt6991 - without it normal boot cannot mount
                            the dynamic partitions at all

Usage:
    extract_ramdisk_files.py --ramdisk vendor_ramdisk00 --dest prebuilt/ramdisk
"""

import argparse
import gzip
import lzma
import os
import struct
import sys

LZ4_LEGACY_MAGIC = 0x184C2102
LZ4_MAX_BLOCK = 8 << 20
S_IFMT = 0o170000
S_IFREG = 0o100000
DEFAULT_PATHS = ("lib/modules", "vendor/firmware", "first_stage_ramdisk")


def lz4_block_decompress(src):
    dst = bytearray()
    pos = 0
    end = len(src)
    while pos < end:
        token = src[pos]
        pos += 1
        literals = token >> 4
        if literals == 15:
            while True:
                extra = src[pos]
                pos += 1
                literals += extra
                if extra != 255:
                    break
        dst += src[pos:pos + literals]
        pos += literals
        if pos >= end:
            break
        offset = src[pos] | (src[pos + 1] << 8)
        pos += 2
        if offset == 0 or offset > len(dst):
            raise ValueError("corrupt LZ4 match offset")
        match_len = token & 0x0F
        if match_len == 15:
            while True:
                extra = src[pos]
                pos += 1
                match_len += extra
                if extra != 255:
                    break
        match_len += 4
        start = len(dst) - offset
        for i in range(match_len):
            dst.append(dst[start + i])
    return bytes(dst)


def lz4_legacy_decompress(data):
    out = bytearray()
    pos = 0
    while pos + 4 <= len(data):
        if struct.unpack_from("<I", data, pos)[0] != LZ4_LEGACY_MAGIC:
            break
        pos += 4
        while pos + 4 <= len(data):
            block_size = struct.unpack_from("<I", data, pos)[0]
            if block_size == 0 or block_size > LZ4_MAX_BLOCK:
                break
            pos += 4
            out += lz4_block_decompress(data[pos:pos + block_size])
            pos += block_size
    return bytes(out)


def decompress(data):
    if data[:4] == b"\x02\x21\x4c\x18":
        return lz4_legacy_decompress(data)
    if data[:2] == b"\x1f\x8b":
        return gzip.decompress(data)
    if data[:6] == b"\xfd7zXZ\x00":
        return lzma.decompress(data)
    return data


def cpio_members(data):
    pos = 0
    while pos + 110 <= len(data):
        header = data[pos:pos + 110]
        if header[:6] not in (b"070701", b"070702"):
            return
        fields = [int(header[6 + i * 8:14 + i * 8], 16) for i in range(13)]
        mode, size, name_size = fields[1], fields[6], fields[11]
        name = data[pos + 110:pos + 110 + name_size - 1].decode("utf-8", "replace")
        body = pos + 110 + name_size
        body += (-body) % 4
        next_pos = body + size
        next_pos += (-next_pos) % 4
        if name == "TRAILER!!!":
            return
        yield name, mode, data[body:body + size]
        pos = next_pos


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ramdisk", required=True, help="PLATFORM ramdisk fragment")
    parser.add_argument("--dest", required=True, help="output directory")
    parser.add_argument("--path", action="append", dest="paths",
                        help="directory to extract, relative to the ramdisk root "
                             "(default: %s)" % ", ".join(DEFAULT_PATHS))
    args = parser.parse_args()

    wanted = tuple(p.rstrip("/") + "/" for p in args.paths or DEFAULT_PATHS)

    with open(args.ramdisk, "rb") as ramdisk_file:
        archive = decompress(ramdisk_file.read())

    os.makedirs(args.dest, exist_ok=True)
    written = {}
    for name, mode, payload in cpio_members(archive):
        if mode & S_IFMT != S_IFREG:
            continue
        if not name.startswith(wanted):
            continue
        target = os.path.join(args.dest, name)
        os.makedirs(os.path.dirname(target), exist_ok=True)
        with open(target, "wb") as out_file:
            out_file.write(payload)
        root = next(p for p in wanted if name.startswith(p))
        written[root] = written.get(root, 0) + 1

    if not written:
        sys.exit("nothing extracted from %s" % args.ramdisk)
    for root, count in sorted(written.items()):
        print("[INFO] Extracted %d files from /%s" % (count, root.rstrip("/")))


if __name__ == "__main__":
    main()
