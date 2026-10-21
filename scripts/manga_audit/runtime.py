"""Isolated, offline execution through the production C ABI.

Never forwards source HTTP/browser requests. Reports contain identifiers/counts,
not exception text, website URLs, cookies, credentials or returned source content.
"""
import base64
import ctypes
import json
from pathlib import Path
import re
import time

OWNED_HTML = b"<!doctype html><html><body></body></html>"
OPS = ("settings", "popular", "latest", "search", "book", "pages", "image")
IDENTIFIER = re.compile(r"^[A-Za-z0-9_$/;<>\[\]().-]{1,1200}$")


def safe_reference(value):
    return (isinstance(value, (list, tuple)) and len(value) == 3
            and all(isinstance(v, str) and IDENTIFIER.fullmatch(v) for v in value)
            and value[0].startswith(("L", "[")) and value[2].startswith("("))


def classify(envelope, requests, browser):
    if envelope.get("ok"):
        data = envelope.get("data")
        count = len(data) if isinstance(data, list) else None
        if isinstance(data, dict) and isinstance(data.get("mangas"), list):
            count = len(data["mangas"])
        return {"status": "ownedResponseAccepted", "entries": count,
                "requests": requests, "browserRequests": browser}
    error = envelope.get("error", "")
    diagnostic = envelope.get("diagnostic") or {}
    kind = diagnostic.get("kind")
    result = {"status": "unclassifiedFailure", "requests": requests,
              "browserRequests": browser}
    api = diagnostic.get("api")
    if isinstance(api, str) and re.fullmatch(r"[A-Za-z0-9_$.]{1,180}", api):
        result["apiClass"] = api
    method = re.match(r"^resolution error: no method (\S+) (\S+) found \(on (\S+)", error)
    if method:
        ref = [method[3].rstrip(")"), method[1], method[2]]
        if safe_reference(ref):
            result["missingMethod"] = ref
    missing_class = re.match(r"^resolution error: class not found: ([^\s]+)", error)
    if missing_class:
        cls = missing_class[1]
        if IDENTIFIER.fullmatch(cls):
            result["missingClass"] = cls
    if (kind == "unsupportedAPI" or method or missing_class
            or error.startswith("resolution error: no static field ")):
        result["status"] = "runtimeAPIError"
    elif kind == "executionLimit" or error in ("instruction budget exceeded", "stack overflow"):
        result["status"] = "executionLimit"
    elif error.startswith("decode error:"):
        result["status"] = "interpreterDecodeError"
    elif browser:
        result["status"] = "browserHarnessRequired"
    return result


class OfflineRuntime:
    def __init__(self, path):
        self.lib = ctypes.CDLL(str(Path(path).resolve()))
        self.libc = ctypes.CDLL(None)
        self.libc.strdup.argtypes = [ctypes.c_char_p]
        self.libc.strdup.restype = ctypes.c_void_p
        self.libc.free.argtypes = [ctypes.c_void_p]
        self.callback_type = ctypes.CFUNCTYPE(ctypes.c_void_p, ctypes.c_void_p, ctypes.c_char_p)
        self.release_type = ctypes.CFUNCTYPE(None, ctypes.c_void_p)
        self.lib.ac_manga_execute.argtypes = [
            ctypes.c_void_p, ctypes.c_size_t, ctypes.c_char_p,
            self.callback_type, self.release_type, ctypes.c_void_p,
        ]
        self.lib.ac_manga_execute.restype = ctypes.c_void_p
        self.lib.ac_manga_free_string.argtypes = [ctypes.c_void_p]

    def execute(self, apk, command):
        requests, browsers = 0, 0

        def host(_context, raw):
            nonlocal requests, browsers
            try:
                request = json.loads(raw)
                requests += 1
                browser = request.get("method") == "AC_BROWSER"
                browsers += int(browser)
                # Match the app's networking-disabled inspection/settings path.
                denied = command["op"] in ("inspect", "settings")
                code = 501 if browser else 599 if denied else 200
                body = b"" if browser or denied else OWNED_HTML
                payload = json.dumps({"code": code,
                    "headers": [["Content-Type", "text/html"]],
                    "bodyBase64": base64.b64encode(body).decode()}).encode()
                return self.libc.strdup(payload)
            except Exception:
                return self.libc.strdup(b'{"code":599,"headers":[],"bodyBase64":""}')

        callback = self.callback_type(host)
        release = self.release_type(self.libc.free)
        buffer = ctypes.create_string_buffer(apk)
        result = self.lib.ac_manga_execute(
            buffer, len(apk), json.dumps(command).encode(), callback, release, None)
        if not result:
            return {"ok": False}, requests, browsers
        try:
            return json.loads(ctypes.string_at(result)), requests, browsers
        finally:
            self.lib.ac_manga_free_string(result)


def probe(library, apk_path, output, modern, seconds=15):
    # A process boundary also bounds native hangs/crashes, not only DEX instructions.
    try:
        import resource
        resource.setrlimit(resource.RLIMIT_AS, (2 * 1024**3, 2 * 1024**3))
        resource.setrlimit(resource.RLIMIT_CPU, (20, 21))
    except (ImportError, ValueError):
        pass
    runtime = OfflineRuntime(library)
    apk = Path(apk_path).read_bytes()
    deadline = time.monotonic() + seconds

    def record(value):
        with Path(output).open("a", encoding="utf-8") as stream:
            stream.write(json.dumps(value, sort_keys=True) + "\n")
            stream.flush()

    envelope, requests, browser = runtime.execute(apk, {"op": "inspect", "modern": modern})
    result = classify(envelope, requests, browser)
    result.update({"record": "operation", "op": "inspect", "source": None})
    record(result)
    if not envelope.get("ok"):
        return
    sources = envelope.get("data", {}).get("sources", [])
    if not isinstance(sources, list) or len(sources) > 512:
        record({"record": "invalidInspection"})
        return
    indices = [s["index"] for s in sources
               if isinstance(s.get("index"), int) and 0 <= s["index"] < 512]
    metadata = [{"index": source["index"], "id": source["id"],
                 "language": source["language"]}
                for source in sources if source.get("index") in indices
                and isinstance(source.get("id"), str)
                and re.fullmatch(r"-?[0-9]{1,20}", source["id"])
                and isinstance(source.get("language"), str)
                and re.fullmatch(r"[A-Za-z0-9-]{1,12}", source["language"])]
    record({"record": "sources", "indices": sorted(set(indices)), "metadata": metadata})
    # Test each actual source instance; unexecuted cells stay explicitly untested.
    latest = {s["index"]: s.get("supportsLatest", False) for s in sources}
    for index in sorted(set(indices)):
        for op in OPS:
            if time.monotonic() >= deadline:
                record({"record": "deadline"})
                return
            if op == "latest" and not latest.get(index):
                record({"record": "operation", "op": op, "source": index,
                        "status": "notAdvertised", "requests": 0, "browserRequests": 0})
                continue
            command = {"op": op, "source": index, "modern": modern}
            if op == "search":
                command["query"] = "Owned audit query"
            if op == "book":
                command["manga"] = {"url": "/owned-series", "title": "Owned story"}
            if op == "pages":
                command["chapter"] = {"url": "/owned-chapter", "name": "Owned chapter"}
            if op == "image":
                command["image"] = {"index": 0, "url": "/owned-chapter",
                                    "imageURL": "https://images.example/owned.png"}
            envelope, requests, browser = runtime.execute(apk, command)
            result = classify(envelope, requests, browser)
            result.update({"record": "operation", "op": op, "source": index})
            record(result)
