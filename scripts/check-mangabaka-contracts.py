#!/usr/bin/env python3
"""Public API contract smoke check; no account, credentials or image downloads.

Print structure rather than catalog text so schema failures can be diagnosed
without copying book descriptions, artwork or private account information.
"""
import json
import time
import urllib.parse
import urllib.request


def shape(value, depth=0):
    if depth >= 5:
        return type(value).__name__
    if isinstance(value, dict):
        return {key: shape(item, depth + 1) for key, item in value.items()}
    if isinstance(value, list):
        return {"count": len(value), "item": shape(value[0], depth + 1) if value else None}
    return type(value).__name__


def request(path, params=()):
    url = "https://api.mangabaka.org" + path
    if params:
        url += "?" + urllib.parse.urlencode(params)
    req = urllib.request.Request(url, headers={
        "Accept": "application/json",
        "User-Agent": "AnimeCompanion/0.25 (https://github.com/goon-123/AnimeCompanion)",
    })
    with urllib.request.urlopen(req, timeout=25) as response:
        data = json.loads(response.read(16_000_001))
    print(path + " " + json.dumps(shape(data), separators=(",", ":")), flush=True)
    assert isinstance(data.get("data"), (dict, list)), "Missing data envelope: " + path
    time.sleep(0.4)
    return data["data"]


if __name__ == "__main__":
    genres = request("/v1/genres")
    tags = request("/v1/tags")
    assert genres and tags, "Taxonomy must be available"
    request("/v1/series/1")
    request("/v1/series/1/images", [("limit", "2")])
    ratings = [("content_rating", "safe"), ("content_rating", "suggestive"), ("limit", "2")]
    for path in ["/v1/series/1/relationships", "/v2/series/1/similar", "/v2/series/1/readers-also-like"]:
        request(path, ratings)
    print("MangaBaka discovery contracts reachable", flush=True)
