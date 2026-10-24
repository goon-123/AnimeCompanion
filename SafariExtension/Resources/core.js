/* Shared by the Safari background, isolated content script and page observer. */
(function (root, factory) {
  const api = factory();
  if (typeof window === "undefined" && typeof module === "object" && module.exports) module.exports = api;
  else if (!root.ACVideo) Object.defineProperty(root, "ACVideo", { value: api });
})(globalThis, function () {
  "use strict";
  const CHANNEL = "animecompanion.video.v1";
  const MAX_AGE = 60 * 60 * 1000;
  const MAX_URL = 16384;
  const DEFAULTS = Object.freeze({ enabled: true, autoPrompt: true, handoff: "compatible", disabledHosts: [] });
  const SAMPLE_URL = "https://developer.mozilla.org/shared-assets/videos/flower.mp4";
  const text = (value, limit = 180) => typeof value === "string" ? value.replace(/[\u0000-\u001f\u007f]/g, " ").trim().slice(0, limit) : "";
  const position = value => Number.isFinite(value) ? Math.min(31536000, Math.max(0, value)) : 0;
  function networkURL(value, base) {
    if (typeof value !== "string" || !value.trim() || value.length > MAX_URL) return null;
    try {
      const url = new URL(value.trim(), base);
      return ["http:", "https:"].includes(url.protocol) && url.hostname ? url.href : null;
    } catch { return null; }
  }
  function host(value) {
    try { return new URL(value).hostname.toLowerCase(); } catch { return ""; }
  }
  function kind(value, mime = "", allowUnknown = false) {
    const url = networkURL(value);
    if (!url) return null;
    const path = new URL(url).pathname.toLowerCase();
    // Transport chunks and encryption keys are never standalone video choices.
    if (/\.(?:ts|m4s|cmfv|cmfa|aac|mp3|key)(?:$|\/)/i.test(path)) return null;
    if (/\.m3u8$/.test(path)) return "HLS";
    if (/\.mpd$/.test(path)) return "DASH";
    if (/\.(mp4|m4v|mov|mkv|webm|avi|wmv|flv|ogv)$/.test(path)) return path.split(".").pop().toUpperCase();
    const type = String(mime).split(";")[0].trim().toLowerCase();
    if (["application/vnd.apple.mpegurl", "application/x-mpegurl", "audio/mpegurl", "audio/x-mpegurl"].includes(type)) return "HLS";
    if (type === "application/dash+xml") return "DASH";
    if (type.startsWith("video/") && !["video/mp2t", "video/iso.segment"].includes(type)) return "Video";
    return allowUnknown ? "Video" : null;
  }
  function options(value = {}) {
    if (!value || typeof value !== "object") value = {};
    return {
      enabled: value.enabled !== false,
      autoPrompt: value.autoPrompt !== false,
      handoff: value.handoff === "resume" ? "resume" : "compatible",
      disabledHosts: [...new Set((Array.isArray(value.disabledHosts) ? value.disabledHosts : [])
        .filter(x => typeof x === "string" && x.length <= 253 && /^[a-z0-9.:[\]-]+$/i.test(x))
        .map(x => x.toLowerCase()))].slice(0, 500)
    };
  }
  function allowed(pageURL, prefs) {
    const name = host(pageURL);
    return Boolean(name && prefs.enabled && !prefs.disabledHosts.includes(name));
  }
  function timestamp(value, now) {
    return Number.isFinite(value) && value >= now - MAX_AGE && value <= now + 5000 ? Math.min(value, now) : now;
  }
  function cleanReport(value, now = Date.now()) {
    if (!value || typeof value !== "object") return null;
    const pageURL = networkURL(value.pageURL);
    if (!pageURL) return null;
    const candidates = (Array.isArray(value.candidates) ? value.candidates : []).slice(-24).flatMap(item => {
      if (!item || typeof item !== "object") return [];
      const url = networkURL(item.url, pageURL);
      const format = kind(url, item.mime, item.source === "video");
      if (!url || !format) return [];
      return [{ url, kind: format, mime: text(item.mime, 100), source: ["video", "fetch", "xhr", "resource", "link"].includes(item.source) ? item.source : "resource", seenAt: timestamp(item.seenAt, now) }];
    });
    const videos = (Array.isArray(value.videos) ? value.videos : []).slice(0, 12).flatMap(item => {
      if (!item || typeof item !== "object" || typeof item.id !== "string") return [];
      return [{
        id: text(item.id, 100), url: networkURL(item.url, pageURL), title: text(item.title),
        position: position(item.position), playing: item.playing === true, protected: item.protected === true,
        visible: item.visible === true, muted: item.muted === true, userInitiated: item.userInitiated === true,
        area: Number.isFinite(item.area) ? Math.min(100000000, Math.max(0, item.area)) : 0,
        startedAt: timestamp(item.startedAt, now), updatedAt: now
      }];
    });
    return { pageURL, title: text(value.title), candidates, videos, updatedAt: now };
  }
  function filename(value) {
    try { return text(decodeURIComponent(new URL(value).pathname.split("/").pop())) || "Video"; }
    catch { return "Video"; }
  }
  function state(tab, prefs = DEFAULTS, now = Date.now()) {
    prefs = options(prefs);
    const pageURL = networkURL(tab?.pageURL) || "";
    const result = { host: host(pageURL), pageURL, options: prefs, enabled: allowed(pageURL, prefs), candidates: [] };
    if (!result.enabled) return result;
    const choices = new Map();
    for (const [frameID, frame] of Object.entries(tab?.frames || {})) {
      if (now - frame.updatedAt > MAX_AGE) continue;
      const videos = frame.videos || [];
      const active = videos.filter(v => v.playing && now - v.updatedAt < 10000)
        .sort((a, b) => Number(b.userInitiated) - Number(a.userInitiated) || b.area - a.area)[0];
      const direct = videos.filter(v => v.url && !v.protected).map(v => ({ url: v.url, kind: kind(v.url, "", true), source: "video", seenAt: frame.updatedAt }));
      for (const item of [...(frame.candidates || []), ...direct]) {
        if (!item.kind || now - item.seenAt > MAX_AGE) continue;
        const exact = videos.find(v => v.url === item.url);
        if (exact?.protected || (!exact && (active?.protected || (!active && videos.some(v => v.protected))))) continue;
        // A blob player can be associated only with recent streams in its own
        // frame. Never borrow timestamps from an unrelated iframe or video.
        const associated = exact || (active && !active.url && item.seenAt >= active.startedAt - 60000 ? active : null);
        const playing = Boolean(associated && associated === active && !associated.protected);
        const automatic = Boolean(playing && associated.visible && (associated.area >= 14400 || associated.userInitiated)
          && (!associated.muted || associated.userInitiated));
        const master = /(?:master|index|playlist)\.m3u8(?:\?|$)/i.test(item.url) ? 30 : 0;
        const score = (playing ? 1000 : 0) + (exact ? 500 : 0) + (automatic ? 200 : 0)
          + (item.kind === "HLS" ? 40 : 0) + master + (associated?.userInitiated ? 50 : 0);
        const candidate = {
          url: item.url, kind: item.kind, host: host(item.url), title: text(associated?.title || frame.title) || filename(item.url),
          filename: filename(item.url), position: associated ? associated.position : 0, playing, automatic,
          frameId: Number(frameID), playbackId: associated?.id || "", score, seenAt: item.seenAt
        };
        const previous = choices.get(item.url);
        if (!previous || score > previous.score || (score === previous.score && item.seenAt > previous.seenAt)) choices.set(item.url, candidate);
      }
    }
    result.candidates = [...choices.values()].sort((a, b) => b.score - a.score || b.seenAt - a.seenAt).slice(0, 40);
    return result;
  }
  function launchURL(candidate, method = "compatible") {
    const url = networkURL(candidate?.url);
    if (!url) throw new Error("This video does not have an accessible stream URL.");
    // RFC 3986 encoding, rather than form encoding (+), preserves signed links
    // and works with native URLQueryItem parsing. Encode every value once.
    // Safari does not need tracking callbacks. Use VidHub's minimal Apple
    // compatibility opener by default; resume is an explicit alternative.
    // Do not override the media filename with an arbitrary webpage title.
    const resume = method === "resume";
    const fields = resume ? { url, position: String(Math.floor(position(candidate.position))) } : { url };
    return "open-vidhub://x-callback-url/" + (resume ? "play" : "open") + "?"
      + Object.entries(fields).map(([key, value]) => encodeURIComponent(key) + "=" + encodeURIComponent(value)).join("&");
  }
  async function copyURL(value) {
    const url = networkURL(value);
    if (!url) throw new Error("No stream link to copy.");
    try {
      if (globalThis.navigator?.clipboard?.writeText) { await navigator.clipboard.writeText(url); return; }
    } catch { /* Safari may require its user-gesture clipboard fallback. */ }
    const doc = globalThis.document;
    if (!doc?.body) throw new Error("Copy is unavailable on this page.");
    const input = doc.createElement("textarea"); input.value = url; input.readOnly = true;
    input.style.cssText = "position:fixed;left:-9999px;top:0;opacity:0";
    doc.body.append(input); input.select();
    try { if (!doc.execCommand("copy")) throw new Error("Copy is unavailable on this page."); }
    finally { input.remove(); }
  }
  return Object.freeze({ CHANNEL, MAX_AGE, MAX_URL, DEFAULTS, SAMPLE_URL, text, position, networkURL, host, kind, options, allowed, cleanReport, state, launchURL, copyURL });
});
