const { test } = require("node:test");
const assert = require("node:assert/strict");
const path = require("node:path");
const { resources, report } = require("./helpers.cjs");
const V = require(path.join(resources, "core.js"));
const tab = value => ({ pageURL: "https://watch.example/episode", frames: { 0: V.cleanReport(value) } });

test("MAIN-world installation does not overwrite a website's CommonJS module exports", () => {
  const vm = require("node:vm");
  const { script } = require("./helpers.cjs");
  const exports = { siteOwned: true };
  const context = vm.createContext({ window: {}, module: { exports }, URL });
  vm.runInContext(script("core.js"), context);
  assert.equal(context.module.exports, exports);
  assert.equal(typeof context.ACVideo.launchURL, "function");
});

test("VidHub handoff preserves signed query strings, Unicode titles, and the current position", () => {
  const video = { url: "https://cdn.example/video.mp4?signature=a+b%2Fc==&expires=123&name=part%201", title: "Señor & friends + episode 4", position: 142.9 };
  const link = V.launchURL(video);
  const values = Object.fromEntries(new URL(link).searchParams);
  assert.equal(values.url, video.url);
  assert.equal(values.filename, video.title);
  assert.equal(values.position, "142");
  assert.equal(link.includes("Se%C3%B1or%20%26%20friends%20%2B"), true);
  assert.equal(values["x-success"], undefined, "Safari videos must not write anime tracking callbacks");
});
test("browser-only and executable addresses cannot be passed to VidHub", () => {
  for (const url of ["blob:https://site.example/id", "javascript:alert(1)", "data:video/mp4;base64,AA", "file:///private/video.mp4", "open-vidhub://x-callback-url/play", "", "x".repeat(17000)]) {
    assert.equal(V.networkURL(url), null);
    assert.throws(() => V.launchURL({ url }));
  }
  for (const position of [NaN, Infinity, -4]) assert.equal(new URL(V.launchURL({ url: "https://site.example/video", position })).searchParams.get("position"), "0");
});
test("HLS, DASH, extensionless video responses, and direct sources are recognized without listing transport chunks", () => {
  assert.equal(V.kind("https://cdn.example/stream", "application/vnd.apple.mpegurl; charset=utf8"), "HLS");
  assert.equal(V.kind("https://cdn.example/stream", "video/mp4"), "Video");
  assert.equal(V.kind("https://cdn.example/manifest.mpd?sig=1"), "DASH");
  assert.equal(V.kind("https://cdn.example/no-extension", "", true), "Video");
  for (const path of ["001.ts", "chunk.m4s", "secret.key", "audio.aac", "page.html"]) assert.equal(V.kind("https://cdn.example/" + path), null);
  const cleaned = V.cleanReport(report({ candidates: [{ url: "https://cdn.example/stream?token=signed", mime: "application/vnd.apple.mpegurl", source: "fetch" }] }));
  assert.equal(V.cleanReport(cleaned).candidates[0].kind, "HLS", "MIME evidence must survive both isolated-script and background validation");
});
test("an actual playing video ranks ahead of unrelated links and retains its own timestamp", () => {
  const value = report({
    candidates: [{ url: "https://cdn.example/ad.mp4", source: "fetch", seenAt: Date.now() }],
    videos: [{ id: "main:1", url: "https://cdn.example/main.mp4", position: 72, playing: true, visible: true, area: 200000, muted: false }]
  });
  const state = V.state(tab(value));
  assert.equal(state.candidates[0].url, "https://cdn.example/main.mp4");
  assert.equal(state.candidates[0].automatic, true);
  assert.equal(state.candidates[0].position, 72);
  assert.equal(state.candidates[1].position, 0);
  assert.equal(state.candidates[1].automatic, false);
});
test("a blob player can use its own frame's manifest but never another frame's timestamp", () => {
  const entry = tab(report());
  entry.frames[7] = V.cleanReport(report({ pageURL: "https://embed.example/player", candidates: [{ url: "https://cdn.example/other.mp4", source: "link" }], videos: [] }));
  const state = V.state(entry);
  assert.equal(state.candidates[0].kind, "HLS");
  assert.equal(state.candidates[0].position, 142.5);
  assert.equal(state.candidates.find(x => x.url.endsWith("other.mp4")).position, 0);
});
test("muted autoplay, invisible players, stale playback, and encrypted videos do not create automatic prompts", () => {
  for (const change of [{ muted: true }, { visible: false }, { area: 0 }]) {
    const state = V.state(tab(report({ videos: [{ ...report().videos[0], ...change }] })));
    assert.equal(state.candidates.some(x => x.automatic), false);
  }
  const protectedTab = tab(report({ videos: [{ ...report().videos[0], protected: true }] }));
  assert.equal(V.state(protectedTab).candidates.length, 0);
  protectedTab.frames[0].videos[0].playing = false;
  assert.equal(V.state(protectedTab).candidates.length, 0, "Paused DRM playback must not expose its manifest as a playable choice");
  const stale = tab(report());
  assert.equal(V.state(stale, V.DEFAULTS, Date.now() + 11000).candidates.some(x => x.automatic), false);
});
test("website opt-outs and global settings suppress candidates without breaking manual-only mode", () => {
  assert.equal(V.state(tab(report()), V.options({ enabled: false })).candidates.length, 0);
  assert.equal(V.state(tab(report()), V.options({ disabledHosts: ["watch.example"] })).enabled, false);
  assert.equal(V.state(tab(report()), V.options({ autoPrompt: false })).candidates.length, 1);
  assert.equal(V.options(null).enabled, true);
});
test("malformed and oversized reports are bounded and stripped of unsupported data", () => {
  const value = V.cleanReport(report({ title: "<img src=x onerror=alert(1)>".repeat(50), candidates: Array.from({ length: 200 }, (_, n) => ({ url: `https://cdn.example/${n}.mp4`, source: "fetch", cookies: "secret" })) }));
  assert.equal(value.candidates.length, 24);
  assert.ok(value.title.length <= 180);
  assert.equal(value.candidates[0].cookies, undefined);
  assert.equal(V.cleanReport({ pageURL: "javascript:alert(1)" }), null);
});
