"""Bounded DEX declaration inventory. Unmatched references are candidates, not failures."""
import io
import re
import struct
import zipfile

MAX_APK = 32 * 1024 * 1024
MAX_EXPANDED = 96 * 1024 * 1024
MAX_ITEMS = 1_000_000
HOST_PREFIXES = (
    "Ljava/", "Ljavax/", "Lkotlin/", "Lkotlinx/", "Landroid/", "Landroidx/",
    "Lokhttp3/", "Lokio/", "Lorg/jsoup/", "Leu/kanade/tachiyomi/",
    "Lkeiyoushi/", "Luy/kohesive/",
)


class DexError(ValueError):
    pass


class Dex:
    def __init__(self, data):
        self.data = data
        self.cache = {}
        self.string_offsets = {}
        self.signatures = {}
        self.identifier_bytes = 0
        self.scan_budget = MAX_ITEMS * 4
        if len(data) < 112 or not re.fullmatch(rb"dex\n0[34][0-9]\0", data[:8]):
            raise DexError("Unsupported DEX header")
        if self.u32(32) != len(data) or self.u32(36) < 112 or self.u32(40) != 0x12345678:
            raise DexError("Invalid DEX size or byte order")
        self.strings = self.table(56, 4)
        self.types = self.table(64, 4)
        self.protos = self.table(72, 12)
        self.fields = self.table(80, 8)
        self.methods = self.table(88, 8)
        self.classes = self.table(96, 32)

    def need(self, offset, size):
        if offset < 0 or size < 0 or offset + size > len(self.data):
            raise DexError("DEX range outside file")

    def u32(self, offset):
        self.need(offset, 4)
        return struct.unpack_from("<I", self.data, offset)[0]

    def table(self, header, width):
        size, offset = self.u32(header), self.u32(header + 4)
        if size > MAX_ITEMS:
            raise DexError("DEX table exceeds item limit")
        self.need(offset, size * width)
        return offset, size

    def item(self, table, index, width):
        offset, size = table
        if not 0 <= index < size:
            raise DexError("DEX index outside table")
        return offset + index * width

    def uleb(self, offset):
        self.scan_budget -= 1
        if self.scan_budget < 0:
            raise DexError("DEX metadata exceeds work limit")
        result = 0
        for shift in range(0, 35, 7):
            self.need(offset, 1)
            value = self.data[offset]
            offset += 1
            if shift == 28 and value > 15:
                raise DexError("ULEB32 overflow")
            result |= (value & 127) << shift
            if not value & 128:
                return result, offset
        raise DexError("Invalid ULEB32")

    def string(self, index):
        if index not in self.cache:
            offset = self.u32(self.item(self.strings, index, 4))
            _, offset = self.uleb(offset)
            if offset in self.string_offsets:
                self.cache[index] = self.string_offsets[offset]
                return self.cache[index]
            end = self.data.find(b"\0", offset, min(offset + 65_537, len(self.data)))
            if end < 0:
                raise DexError("Unterminated or oversized identifier")
            # Only identifiers/descriptors are requested, never guest content strings.
            self.identifier_bytes += end - offset
            if self.identifier_bytes > 8 * 1024 * 1024:
                raise DexError("DEX identifiers exceed byte limit")
            self.cache[index] = self.data[offset:end].decode("utf-8", errors="replace")
            self.string_offsets[offset] = self.cache[index]
        return self.cache[index]

    def type(self, index):
        return self.string(self.u32(self.item(self.types, index, 4)))

    def type_list(self, offset):
        if not offset:
            return []
        size = self.u32(offset)
        if size > 65_535:
            raise DexError("DEX type list exceeds limit")
        self.scan_budget -= size
        if self.scan_budget < 0:
            raise DexError("DEX type lists exceed work limit")
        self.need(offset + 4, size * 2)
        return [self.type(struct.unpack_from("<H", self.data, offset + 4 + i * 2)[0])
                for i in range(size)]

    def method(self, index):
        offset = self.item(self.methods, index, 8)
        owner, proto, name = struct.unpack_from("<HHI", self.data, offset)
        if proto not in self.signatures:
            p = self.item(self.protos, proto, 12)
            signature = "(" + "".join(self.type_list(self.u32(p + 8))) + ")" + self.type(self.u32(p + 4))
            if len(signature) > 16_384:
                raise DexError("DEX method signature exceeds byte limit")
            self.signatures[proto] = signature
        return self.type(owner), self.string(name), self.signatures[proto]

    def inventory(self):
        refs = {self.method(i) for i in range(self.methods[1])}
        declared, native, parents = set(), set(), {}
        for i in range(self.classes[1]):
            offset = self.item(self.classes, i, 32)
            owner, _, superclass, interfaces, _, _, class_data, _ = struct.unpack_from(
                "<8I", self.data, offset)
            descriptor = self.type(owner)
            if descriptor in parents:
                raise DexError("Duplicate DEX class definition")
            parents[descriptor] = ([] if superclass == 0xFFFFFFFF else [self.type(superclass)])
            parents[descriptor] += self.type_list(interfaces)
            if not class_data:
                continue
            counts = []
            for _ in range(4):
                count, class_data = self.uleb(class_data)
                if count > MAX_ITEMS:
                    raise DexError("DEX declarations exceed limit")
                counts.append(count)
            for _ in range(counts[0] + counts[1]):
                _, class_data = self.uleb(class_data)
                _, class_data = self.uleb(class_data)
            for count in counts[2:]:
                method_index = 0
                for _ in range(count):
                    delta, class_data = self.uleb(class_data)
                    access, class_data = self.uleb(class_data)
                    _, class_data = self.uleb(class_data)
                    method_index += delta
                    method = self.method(method_index)
                    if method[0] != descriptor:
                        raise DexError("Method declared by wrong class")
                    (native if access & 0x100 else declared).add(method)
        return {"references": refs, "declared": declared, "native": native, "parents": parents}


def apk_inventory(data):
    if not 0 < len(data) <= MAX_APK:
        raise DexError("APK exceeds byte limit")
    result = {"references": set(), "declared": set(), "native": set(), "parents": {}}
    with zipfile.ZipFile(io.BytesIO(data)) as archive:
        entries = archive.infolist()
        if len(entries) > 4096 or sum(i.file_size for i in entries) > MAX_EXPANDED:
            raise DexError("APK expands beyond limit")
        dexes = [i for i in entries if re.fullmatch(r"classes(?:[2-9]|[1-9][0-9]+)?\.dex", i.filename)]
        if not dexes or len(dexes) > 64:
            raise DexError("Invalid DEX file count")
        for entry in dexes:
            inventory = Dex(archive.read(entry)).inventory()
            for key in ("references", "declared", "native"):
                result[key].update(inventory[key])
            result["parents"].update(inventory["parents"])
            if len(result["references"]) > MAX_ITEMS or len(result["parents"]) > MAX_ITEMS:
                raise DexError("APK declarations exceed item limit")
    return result


def unmatched_references(inventory, capabilities, bundled=None):
    """Follow known guest and host ancestry; dynamic dispatch still needs execution."""
    provided = set(map(tuple, capabilities["methods"]))
    parents = dict(capabilities.get("parents", {}))
    if bundled:
        provided.update(bundled["declared"])
        parents.update(bundled["parents"])
    provided.update(inventory["declared"])
    parents.update(inventory["parents"])

    budget = MAX_ITEMS * 4

    def resolves(method):
        nonlocal budget
        owner, name, signature = method
        pending, visited = [owner], set()
        while pending:
            cls = pending.pop()
            if cls in visited:
                continue
            visited.add(cls)
            budget -= 1
            if budget < 0:
                raise DexError("Ancestry resolution exceeds work limit")
            if len(visited) > 512:
                return False
            if (cls, name, signature) in provided:
                return True
            if name not in ("<init>", "<clinit>"):
                pending.extend(parents.get(cls, []))
        return False

    return sorted(ref for ref in inventory["references"] if not resolves(ref))
