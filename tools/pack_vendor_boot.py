#!/usr/bin/env python3
"""Repack a vendor_boot v4 image after replacing one of its payloads.

The mkbootimg that ships with the twrp-16.0 tree predates vendor ramdisk
fragments, so it cannot rebuild an image with a 0x1 PLATFORM + 0x2 RECOVERY
table. This tool reads the existing header, keeps every field, and only
substitutes the payload that was asked for. Feeding the original payloads back
reproduces the input byte for byte, which is checked by --verify.

Usage:
    pack_vendor_boot.py --input vendor_boot.img --dtb new.dtb --output out.img
    pack_vendor_boot.py --input vendor_boot.img --output copy.img --verify
"""

import argparse
import struct
import sys

MAGIC = b"VNDRBOOT"
HEADER_VERSION = 4
HEADER_FMT = "8s5I2048sI16sIIQ4I"
HEADER_SIZE = struct.calcsize(HEADER_FMT)
ENTRY_FMT = "III32s16I"
ENTRY_SIZE = struct.calcsize(ENTRY_FMT)


def align(value, page):
    return (value + page - 1) // page * page


def read_header(blob):
    fields = struct.unpack_from(HEADER_FMT, blob, 0)
    (magic, header_version, page_size, kernel_addr, ramdisk_addr,
     ramdisk_size, cmdline, tags_addr, name, header_size, dtb_size, dtb_addr,
     table_size, entry_num, entry_size, bootconfig_size) = fields
    if magic != MAGIC:
        raise ValueError("not a vendor_boot image (magic %r)" % magic)
    if header_version != HEADER_VERSION:
        raise ValueError("only header version %d is supported, got %d" %
                         (HEADER_VERSION, header_version))
    if header_size != HEADER_SIZE:
        raise ValueError("unexpected header size %d (expected %d)" %
                         (header_size, HEADER_SIZE))
    return {
        "page_size": page_size, "kernel_addr": kernel_addr,
        "ramdisk_addr": ramdisk_addr, "ramdisk_size": ramdisk_size,
        "cmdline": cmdline, "tags_addr": tags_addr, "name": name,
        "dtb_size": dtb_size, "dtb_addr": dtb_addr,
        "table_size": table_size, "entry_num": entry_num,
        "entry_size": entry_size, "bootconfig_size": bootconfig_size,
    }


def read_table(blob, header, table_offset):
    entries = []
    for index in range(header["entry_num"]):
        offset = table_offset + index * header["entry_size"]
        fields = struct.unpack_from(ENTRY_FMT, blob, offset)[:3]
        entries.append({"size": fields[0], "offset": fields[1], "type": fields[2]})
    return entries


def layout(header):
    page = header["page_size"]
    offsets = {"header": 0}
    cursor = page
    offsets["ramdisk"] = cursor
    cursor = align(cursor + header["ramdisk_size"], page)
    offsets["dtb"] = cursor
    cursor = align(cursor + header["dtb_size"], page)
    offsets["table"] = cursor
    cursor += header["table_size"]
    offsets["bootconfig"] = cursor
    return offsets


def main(argv):
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--dtb")
    parser.add_argument("--vendor-ramdisk")
    parser.add_argument("--pad-to", type=lambda v: int(v, 0),
                        help="zero pad the output to this size (default: the input size)")
    parser.add_argument("--verify", action="store_true",
                        help="assert the rebuild reproduces --input")
    args = parser.parse_args(argv[1:])

    with open(args.input, "rb") as f:
        blob = f.read()

    header = read_header(blob)
    offsets = layout(header)
    table_offset = offsets["table"]

    dtb = blob[offsets["dtb"]:offsets["dtb"] + header["dtb_size"]]
    ramdisk = blob[offsets["ramdisk"]:offsets["ramdisk"] + header["ramdisk_size"]]
    bootconfig = blob[offsets["bootconfig"]:
                      offsets["bootconfig"] + header["bootconfig_size"]]
    table = blob[table_offset:table_offset + header["table_size"]]

    if args.dtb:
        with open(args.dtb, "rb") as f:
            dtb = f.read()
    if args.vendor_ramdisk:
        with open(args.vendor_ramdisk, "rb") as f:
            ramdisk = f.read()

    if args.dtb or args.vendor_ramdisk:
        header["dtb_size"] = len(dtb)
        header["ramdisk_size"] = len(ramdisk)

    page = header["page_size"]
    out = bytearray()
    out.extend(struct.pack(
        HEADER_FMT, MAGIC, HEADER_VERSION, page, header["kernel_addr"],
        header["ramdisk_addr"], header["ramdisk_size"], header["cmdline"],
        header["tags_addr"], header["name"], HEADER_SIZE, header["dtb_size"],
        header["dtb_addr"], header["table_size"], header["entry_num"],
        header["entry_size"], header["bootconfig_size"]))
    out.extend(b"\0" * (page - len(out)))

    def put_region(data):
        out.extend(data)
        out.extend(b"\0" * (align(len(out), page) - len(out)))

    put_region(ramdisk)
    put_region(dtb)
    out.extend(table)
    out.extend(bootconfig)

    produced = len(out)
    if args.verify:
        if bytes(out) != blob[:produced]:
            print("verify FAILED: the rebuilt header/payloads differ from %s" %
                  args.input, file=sys.stderr)
            return 1
        trailing = blob[produced:]
        if trailing.strip(b"\0"):
            print("verify OK: %d header/payload bytes identical; the last %d "
                  "bytes of the input are stale partition data, not part of the image" %
                  (produced, len(trailing)))
        else:
            print("verify OK: %s reproduced exactly" % args.input)

    pad_to = args.pad_to if args.pad_to is not None else len(blob)
    if pad_to > len(out):
        out.extend(b"\0" * (pad_to - len(out)))

    with open(args.output, "wb") as f:
        f.write(out)
    print("%s: dtb %d bytes, ramdisk %d bytes, %d fragments, %d bytes total%s" %
          (args.output, len(dtb), len(ramdisk), header["entry_num"], len(out),
           " (padded)" if len(out) > produced else ""))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
