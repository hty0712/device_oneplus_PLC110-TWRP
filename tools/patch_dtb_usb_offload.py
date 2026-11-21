#!/usr/bin/env python3
"""Unbind the MediaTek USB-offload gate from the xHCI node (base DTB only).

mtu3 refuses to switch the DR port to host until the offload driver has
registered itself (drivers/usb/mtu3/mtu3_dr.c):

    if (role == USB_ROLE_HOST && ssusb->offload_support && !ssusb->offload) {
            dev_info(ssusb->dev, "offload not ready\\n");
            return;
    }

`offload_support` is just "a child of the usb0 node carries the
mediatek,usb-offload property" (mtu3_plat.c, ssusb_plat_probe).  The only driver
that calls ssusb_offload_register() is usb_offload.ko from
/vendor_dlkm/lib/modules, and it cannot probe in recovery: it gives up in
mtk_offload_init_rsv_dram() ("adsp_get_reserve_mblock va_start is NULL")
because nothing starts the ADSP firmware.  The gate therefore never opens, the
port stays in device mode, xhci never registers and an OTG drive is never
enumerated.

The property is not in the base DTB - the OPlus DTBO entries add it with
    fragment@N { target = <&usb_host>; __overlay__ { mediatek,usb-offload = <...>; }; }
and dtbo is authenticated by the bootloader ("[SEC] image dtbo auth fail"), so
it cannot be edited.  What *can* be edited is the base DTB that ships inside
vendor_boot: this tool repoints the `usb_host` symbol of __symbols__ at a new
empty node, so the overlay applies the property there instead of to
/soc/usb0@16701000/xhci0@16700000.

xhci0 stays a child of the usb0 node (mtu3 registers it with
of_platform_populate and looks it up by compatible), it just no longer has the
offload phandle, which makes mtu3 switch the port to host directly and lets
xhci probe with vendor_ops == NULL (every hooks is NULL checked).  The only
feature lost is the ADSP USB-audio offload path; USB audio itself still runs
over the regular xHCI URBs.

prebuilt/dtb is a DTBO table (magic 0xd7b7ab1e) that carries the base DTB; a
bare FDT (0xd00dfeed) is accepted as well.

Usage:
    python3 tools/patch_dtb_usb_offload.py prebuilt/dtb            # in place
    python3 tools/patch_dtb_usb_offload.py stock.dtb patched.dtb
"""

import struct
import sys

FDT_MAGIC = 0xD00DFEED
DTBO_MAGIC = 0xD7B7AB1E
FDT_BEGIN_NODE = 0x1
FDT_END_NODE = 0x2
FDT_PROP = 0x3
FDT_NOP = 0x4
FDT_END = 0x9

OFFLOAD_PROPERTY = "mediatek,usb-offload"
HOST_SYMBOL = "usb_host"
HOLDER_NODE = "usb-offload-holder"
HOLDER_PATH = "/" + HOLDER_NODE


class Node:
    def __init__(self, name):
        self.name = name
        self.props = []      # list of (name, value)
        self.children = []   # list of Node

    def prop(self, name):
        for prop_name, value in self.props:
            if prop_name == name:
                return value
        return None

    def set_prop(self, name, value):
        for index, (prop_name, _) in enumerate(self.props):
            if prop_name == name:
                self.props[index] = (name, value)
                return
        self.props.append((name, value))

    def child(self, name):
        for node in self.children:
            if node.name == name:
                return node
        return None

    def walk(self, prefix=""):
        path = prefix + "/" + self.name if prefix or self.name else prefix
        if self.name == "":
            path = "/"
        yield path, self
        for node in self.children:
            yield from node.walk("" if path == "/" else path)


def _align(value, boundary=4):
    return (value + boundary - 1) // boundary * boundary


def _parse_fdt(blob, base):
    (magic, totalsize, off_struct, off_strings, _, _, _, _,
     size_strings, size_struct) = struct.unpack_from(">10I", blob, base)
    if magic != FDT_MAGIC:
        raise ValueError("no FDT at offset %d (magic 0x%08x)" % (base, magic))
    if base + totalsize > len(blob):
        raise ValueError("FDT at offset %d claims %d bytes, file is %d" %
                         (base, totalsize, len(blob)))

    strings = blob[base + off_strings:base + off_strings + size_strings]
    pos = base + off_struct
    end = pos + size_struct

    def pad4(value):
        # FDT offsets are relative to the blob start, so align relative to base.
        return base + _align(value - base)

    root = None
    stack = []
    while pos + 4 <= end:
        (tag,) = struct.unpack_from(">I", blob, pos)
        pos += 4
        if tag == FDT_BEGIN_NODE:
            nul = blob.find(b"\0", pos, end)
            if nul < 0:
                raise ValueError("unterminated node name at %d" % pos)
            node = Node(blob[pos:nul].decode("ascii", "replace"))
            if stack:
                stack[-1].children.append(node)
            elif root is None:
                root = node
            else:
                raise ValueError("second root node at %d" % pos)
            stack.append(node)
            pos = pad4(nul + 1)
        elif tag == FDT_END_NODE:
            if not stack:
                raise ValueError("unbalanced FDT_END_NODE at %d" % pos)
            stack.pop()
        elif tag == FDT_PROP:
            (prop_len, name_off) = struct.unpack_from(">II", blob, pos)
            pos += 8
            name_end = strings.find(b"\0", name_off)
            if name_end < 0:
                raise ValueError("bad property name offset %d" % name_off)
            name = strings[name_off:name_end].decode("ascii", "replace")
            value = bytes(blob[pos:pos + prop_len])
            stack[-1].props.append((name, value))
            pos = pad4(pos + prop_len)
        elif tag == FDT_NOP:
            pass
        elif tag == FDT_END:
            break
        else:
            raise ValueError("unknown FDT token 0x%x at %d" % (tag, pos))
    if stack:
        raise ValueError("unbalanced FDT node stack")
    if root is None:
        raise ValueError("FDT has no root node")
    return root


def _serialize_fdt(root, rsv_map, boot_cpuid=0):
    strings = bytearray()
    string_offsets = {}

    def string_offset(name):
        offset = string_offsets.get(name)
        if offset is None:
            offset = len(strings)
            string_offsets[name] = offset
            strings.extend(name.encode("ascii") + b"\0")
        return offset

    struct_block = bytearray()

    def emit(node):
        struct_block.extend(struct.pack(">I", FDT_BEGIN_NODE))
        struct_block.extend(node.name.encode("ascii") + b"\0")
        while len(struct_block) % 4:
            struct_block.append(0)
        for name, value in node.props:
            struct_block.extend(struct.pack(">III", FDT_PROP, len(value),
                                            string_offset(name)))
            struct_block.extend(value)
            while len(struct_block) % 4:
                struct_block.append(0)
        for child in node.children:
            emit(child)
        struct_block.extend(struct.pack(">I", FDT_END_NODE))

    emit(root)
    struct_block.extend(struct.pack(">I", FDT_END))

    rsv = bytearray()
    for address, size in rsv_map:
        rsv.extend(struct.pack(">QQ", address, size))
    rsv.extend(b"\0" * 16)

    off_rsvmap = 40
    off_struct = off_rsvmap + len(rsv)
    off_strings = off_struct + len(struct_block)
    # The bootloader sizes the base DTB as (container - table header) and
    # libufdt rejects the overlay when that differs from fdt_totalsize(), so
    # keep the blob free of trailing padding: pad the string table instead.
    while (off_strings + len(strings)) % 8:
        strings.append(0)
    totalsize = off_strings + len(strings)

    out = bytearray()
    out.extend(struct.pack(">10I", FDT_MAGIC, totalsize, off_struct, off_strings,
                           off_rsvmap, 17, 16, boot_cpuid,
                           len(strings), len(struct_block)))
    out.extend(rsv)
    out.extend(struct_block)
    out.extend(strings)
    return bytes(out)


def _read_rsvmap(blob, base, offset):
    entries = []
    pos = base + offset
    while pos + 16 <= len(blob):
        address, size = struct.unpack_from(">QQ", blob, pos)
        pos += 16
        if address == 0 and size == 0:
            break
        entries.append((address, size))
    return entries


def _next_phandle(root):
    """Lowest unused phandle value, above every phandle the tree already has."""
    highest = 0
    for _, node in root.walk():
        for name, value in node.props:
            if name in ("phandle", "linux,phandle") and len(value) == 4:
                highest = max(highest, struct.unpack(">I", value)[0])
    return highest + 1


def patch_fdt(blob, base):
    header = struct.unpack_from(">10I", blob, base)
    root = _parse_fdt(blob, base)
    rsv_map = _read_rsvmap(blob, base, header[4])

    symbols = root.child("__symbols__")
    if symbols is None:
        raise ValueError("base DTB has no __symbols__ node; cannot repoint %s" %
                         HOST_SYMBOL)

    target = symbols.prop(HOST_SYMBOL)
    if target is None:
        raise ValueError("base DTB has no %s symbol; cannot repoint it" % HOST_SYMBOL)
    target_path = target.rstrip(b"\0").decode("ascii", "replace")
    if target_path == HOLDER_PATH:
        return None

    if root.child(HOLDER_NODE) is None:
        holder = Node(HOLDER_NODE)
        # A phandle is mandatory: libufdt resolves an overlay fragment target by
        # reading the phandle of the node the __symbols__ entry points at, and
        # reports "failed to find target 0000" when the node has none.
        holder.set_prop("phandle", struct.pack(">I", _next_phandle(root)))
        holder.set_prop("status", b"okay\0")
        root.children.append(holder)

    symbols.set_prop(HOST_SYMBOL, HOLDER_PATH.encode("ascii") + b"\0")
    return _serialize_fdt(root, rsv_map, header[7])


def patch_image(blob):
    """Return (new_blob, changed) where changed counts repointed FDTs."""
    if len(blob) < 8:
        raise ValueError("file is too small to hold a device tree")

    (magic,) = struct.unpack_from(">I", blob, 0)
    if magic == FDT_MAGIC:
        patched = patch_fdt(blob, 0)
        return (blob, 0) if patched is None else (patched, 1)

    if magic != DTBO_MAGIC:
        raise ValueError("not an FDT (0x%08x) or DTBO table (0x%08x), got 0x%08x" %
                         (FDT_MAGIC, DTBO_MAGIC, magic))

    (_, header_size, entry_size, entry_count,
     entries_offset) = struct.unpack_from(">5I", blob, 4)

    entries = []
    changed = 0
    for index in range(entry_count):
        entry = entries_offset + index * entry_size
        (dt_size, dt_offset) = struct.unpack_from(">II", blob, entry)
        if dt_size == 0 or dt_offset == 0:
            entries.append(None)
            continue
        fdt = blob[dt_offset:dt_offset + dt_size]
        patched = patch_fdt(fdt, 0)
        if patched is not None:
            changed += 1
            entries.append(patched)
        else:
            entries.append(bytes(fdt))

    if changed == 0:
        return blob, 0

    out = bytearray(blob[:entries_offset + entry_count * entry_size])
    for index, fdt in enumerate(entries):
        entry = entries_offset + index * entry_size
        if fdt is None:
            continue
        struct.pack_into(">II", out, entry, len(fdt), len(out))
        out.extend(fdt)
    if len(out) % 8:
        raise ValueError("serialized FDT is not 8 byte aligned; libufdt would "
                         "see a different size than the table advertises")
    struct.pack_into(">I", out, 4, len(out))
    return bytes(out), changed


def main(argv):
    if len(argv) not in (2, 3):
        print("usage: %s <input.dtb> [output.dtb]" % argv[0], file=sys.stderr)
        return 2

    src = argv[1]
    dst = argv[2] if len(argv) == 3 else src
    with open(src, "rb") as f:
        blob = f.read()

    patched, changed = patch_image(blob)
    with open(dst, "wb") as f:
        f.write(patched)

    if changed == 0:
        print("%s: %s already repointed, nothing to do" % (dst, HOST_SYMBOL))
    else:
        print("%s: repointed %d %s symbol(s) to %s (%d -> %d bytes)" %
              (dst, changed, HOST_SYMBOL, HOLDER_PATH, len(blob), len(patched)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
