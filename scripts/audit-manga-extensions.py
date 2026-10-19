#!/usr/bin/env python3
"""Exercise published, hash-verified APKs against the actual on-device C ABI.

Development only. No APK or website content is bundled in the application.
By default the host returns an empty owned HTML document: this separates
missing runtime APIs from unavailable websites. --live makes public catalog
requests (never chapter/image downloads) and keeps cookies within one source.
"""
import argparse
import base64
import ctypes
import gzip
import hashlib
import json
from pathlib import Path
import sys
import urllib.error
import urllib.request
import http.cookiejar


def fields(data):
    offset = 0

    def varint():
        nonlocal offset
        result = 0
        for shift in range(0, 70, 7):
            byte = data[offset]
            offset += 1
            result |= (byte & 127) << shift
            if not byte & 128:
                return result
        raise ValueError("Invalid protobuf")

    result = {}
    while offset < len(data):
        key = varint()
        if key & 7 == 0:
            value = varint()
        elif key & 7 == 2:
            length = varint()
            value = data[offset:offset + length]
            offset += length
        else:
            raise ValueError("Unsupported protobuf field")
        result.setdefault(key >> 3, []).append(value)
    return result


def fetch(url):
    with urllib.request.urlopen(url, timeout=40) as response:
        return response.read(32 * 1024 * 1024 + 1)


def catalog():
    raw = fetch("https://raw.githubusercontent.com/keiyoushi/extensions/repo/index.pb")
    root = fields(gzip.decompress(raw) if raw[:2] == b"\x1f\x8b" else raw)
    checksums = json.loads(fetch("https://raw.githubusercontent.com/keiyoushi/extensions/repo/release-assets.json"))
    for raw_entry in fields(root[101][0])[1]:
        entry = fields(raw_entry)
        pkg = entry[2][0].decode()
        resources = fields(entry[3][0])
        if pkg in checksums:
            yield {"package": pkg, "api": entry[4][0].decode(),
                   "url": resources[1][0].decode(), **checksums[pkg]["apk"]}


class Runtime:
    def __init__(self, library):
        self.lib = ctypes.CDLL(str(library.resolve()))
        self.libc = ctypes.CDLL(None)
        self.libc.strdup.argtypes = [ctypes.c_char_p]
        self.libc.strdup.restype = ctypes.c_void_p
        self.libc.free.argtypes = [ctypes.c_void_p]
        self.callback_type = ctypes.CFUNCTYPE(ctypes.c_void_p, ctypes.c_void_p, ctypes.c_char_p)
        self.release_type = ctypes.CFUNCTYPE(None, ctypes.c_void_p)
        self.lib.ac_manga_execute.argtypes = [ctypes.c_void_p, ctypes.c_size_t, ctypes.c_char_p,
                                             self.callback_type, self.release_type, ctypes.c_void_p]
        self.lib.ac_manga_execute.restype = ctypes.c_void_p
        self.lib.ac_manga_free_string.argtypes = [ctypes.c_void_p]

    def execute(self, apk, command, live=False, owned_response=None):
        requests = []
        opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(http.cookiejar.CookieJar()))

        def host(_context, request):
            request = json.loads(request)
            item = {"url": request["url"], "method": request["method"]}
            requests.append(item)
            status, headers, body = 200, [["Content-Type", "text/html"]], b"<html><body></body></html>"
            if owned_response is not None:
                body = owned_response
            if live:
                try:
                    outbound = urllib.request.Request(request["url"],
                        data=request.get("body", "").encode() if request.get("body") is not None else None,
                        headers=dict(request["headers"]), method=request["method"])
                    try:
                        response = opener.open(outbound, timeout=20)
                    except urllib.error.HTTPError as error:
                        response = error
                    with response:
                        status, headers, body = response.code, list(response.headers.items()), response.read(16_000_001)
                    if len(body) > 16_000_000:
                        raise ValueError("Oversized response")
                except Exception as error:
                    item["networkError"] = str(error)
                    status, headers, body = 599, [], b""
            item["status"] = status
            payload = json.dumps({"code": status, "headers": headers,
                                  "bodyBase64": base64.b64encode(body).decode()}).encode()
            return self.libc.strdup(payload)

        callback = self.callback_type(host)
        release = self.release_type(self.libc.free)
        buffer = ctypes.create_string_buffer(apk)
        result = self.lib.ac_manga_execute(buffer, len(apk), json.dumps(command).encode(), callback, release, None)
        try:
            return {**json.loads(ctypes.string_at(result)), "requests": requests}
        finally:
            self.lib.ac_manga_free_string(result)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--library", type=Path, default=Path("Tools/MangaRuntime/target/debug/deps/libanime_manga_runtime.so"))
    parser.add_argument("--cache", type=Path, default=Path("Tools/MangaRuntime/target/audit-apks"))
    parser.add_argument("--live", action="store_true")
    parser.add_argument("--owned-response", type=Path, help="Owned HTML/JSON response for every catalog request")
    parser.add_argument("--packages", nargs="+", default=[
        "all.mangadex", "all.mangafire", "en.asurascans", "en.comix", "en.manhuaus",
        "en.mangabuddy", "en.mangabat", "en.mangakakalot", "en.mangakatana",
        "en.mangahere", "en.mangafreak", "all.webtoons", "en.weebcentral"])
    args = parser.parse_args()
    runtime = Runtime(args.library)
    args.cache.mkdir(parents=True, exist_ok=True)
    entries = list(catalog())
    for name in args.packages:
        entry = next((e for e in entries if e["package"].endswith(".extension." + name)), None)
        if entry is None:
            print(json.dumps({"package": name, "error": "Not in current catalog"}), flush=True)
            continue
        path = args.cache / entry["name"]
        if not path.exists():
            path.write_bytes(fetch(entry["url"]))
        apk = path.read_bytes()
        if hashlib.sha256(apk).hexdigest() != entry["sha256"]:
            raise ValueError("Package checksum mismatch: " + name)
        inspected = runtime.execute(apk, {"op": "inspect"})
        sources = inspected.get("data", {}).get("sources", [])
        source = next((s for s in sources if s["language"] == "en"), sources[0] if sources else None)
        if source is None:
            output = {"package": name, "version": entry["name"], "inspection": inspected}
        else:
            command = {"op": "popular", "source": source["index"], "modern": entry["api"] == "1.6"}
            output = {"package": name, "version": entry["name"], "source": source,
                      "catalog": runtime.execute(apk, command, args.live,
                          args.owned_response.read_bytes() if args.owned_response else None)}
            if output["catalog"].get("ok"):
                mangas = output["catalog"].pop("data", {}).get("mangas", [])
                output["catalog"]["entries"] = len(mangas)
        print(json.dumps(output), flush=True)


if __name__ == "__main__":
    main()
