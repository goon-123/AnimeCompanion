/* Runs in the page's MAIN world: observes media, never downloads or decrypts it. */
(function () {
  "use strict";
  if (globalThis.__acVideoObserverV1) return;
  Object.defineProperty(globalThis, "__acVideoObserverV1", { value: true });
  const V = globalThis.ACVideo;
  // Before the isolated script supplies website policy, keep only a bounded
  // page-local buffer. This catches very early responses; nothing is reported
  // to the extension until access is enabled, and an opt-out clears the buffer.
  let enabled = null;
  let pending = null;
  let lastReport = 0;
  let lastInteraction = 0;
  let pageURL = location.href;
  let routeStart = 0;
  let sequence = 0;
  const candidates = new Map();
  const roots = new Set();
  const metadata = new WeakMap();
  const xhrURLs = new WeakMap();
  const xhrListeners = new WeakSet();
  function info(video) {
    if (!metadata.has(video)) metadata.set(video, { token: "v" + (++sequence), epoch: 0, source: "", startedAt: Date.now(), protected: false, userInitiated: false });
    const value = metadata.get(video);
    const source = video.currentSrc || video.getAttribute("src") || "";
    if (value.source !== source) {
      value.source = source; value.epoch++; value.startedAt = Date.now(); value.protected = false;
      value.userInitiated = Date.now() - lastInteraction < 5000;
    }
    return value;
  }
  function baseURL() { return V.networkURL(location.href) || V.networkURL(document.baseURI) || V.networkURL(document.referrer); }
  function routeChanged() {
    if (pageURL === location.href) return;
    pageURL = location.href; routeStart = performance.now(); candidates.clear();
    schedule();
  }
  function record(value, mime, source) {
    if (enabled === false) return;
    routeChanged();
    const url = V.networkURL(value, baseURL());
    if (!url || !V.kind(url, mime, source === "video")) return;
    candidates.delete(url);
    candidates.set(url, { url, mime: V.text(mime, 100), source, seenAt: Date.now() });
    while (candidates.size > 24) candidates.delete(candidates.keys().next().value);
    schedule();
  }
  function mediaEvent(event) {
    if (!enabled || !(event.target instanceof HTMLVideoElement)) return;
    const value = info(event.target);
    if (["encrypted", "waitingforkey", "webkitneedkey"].includes(event.type)) value.protected = true;
    if (["play", "playing"].includes(event.type) && Date.now() - lastInteraction < 5000) value.userInitiated = true;
    if (event.type !== "timeupdate" || Date.now() - lastReport > 1500) schedule();
  }
  function observeRoot(root) {
    if (roots.has(root) || roots.size >= 64) return;
    roots.add(root);
    for (const name of ["play", "playing", "pause", "ended", "loadedmetadata", "loadstart", "emptied", "timeupdate", "encrypted", "waitingforkey", "webkitneedkey"])
      root.addEventListener(name, mediaEvent, true);
    new MutationObserver(changes => {
      if (!enabled) return;
      for (const change of changes) for (const node of change.addedNodes) {
        if (node.nodeType !== 1) continue;
        if (node.shadowRoot) observeRoot(node.shadowRoot);
        for (const child of node.querySelectorAll("*")) if (child.shadowRoot) observeRoot(child.shadowRoot);
      }
      if (enabled) schedule();
    }).observe(root, { subtree: true, childList: true, attributes: true, attributeFilter: ["src", "type", "data-src"] });
    for (const node of root.querySelectorAll("*")) if (node.shadowRoot) observeRoot(node.shadowRoot);
  }
  function allVideos() {
    const videos = [];
    for (const root of roots) {
      if (root !== document && !root.host?.isConnected) { roots.delete(root); continue; }
      for (const video of root.querySelectorAll("video")) videos.push(video);
    }
    return [...new Set(videos)].slice(0, 12);
  }
  function videoSnapshot(video) {
    const value = info(video);
    const box = video.getBoundingClientRect();
    const width = Math.max(0, Math.min(innerWidth, box.right) - Math.max(0, box.left));
    const height = Math.max(0, Math.min(innerHeight, box.bottom) - Math.max(0, box.top));
    const visible = width > 0 && height > 0 && document.visibilityState !== "hidden" && getComputedStyle(video).visibility !== "hidden";
    const url = V.networkURL(video.currentSrc || video.getAttribute("src"), baseURL());
    if (url) {
      const old = candidates.get(url);
      candidates.set(url, { url, mime: video.getAttribute("type") || "", source: "video", seenAt: old?.seenAt || Date.now() });
    }
    for (const source of video.querySelectorAll("source[src]")) {
      const link = V.networkURL(source.getAttribute("src"), baseURL());
      if (link && !candidates.has(link)) candidates.set(link, { url: link, mime: source.type, source: "video", seenAt: Date.now() });
    }
    return {
      id: value.token + ":" + value.epoch, url, title: video.getAttribute("title") || document.title,
      position: V.position(video.currentTime), playing: !video.paused && !video.ended,
      protected: value.protected || Boolean(video.mediaKeys), visible, muted: video.muted || video.volume === 0,
      userInitiated: value.userInitiated, area: width * height, startedAt: value.startedAt
    };
  }
  function report() {
    pending = null;
    if (!enabled) return;
    routeChanged();
    const videos = allVideos().map(videoSnapshot);
    const now = Date.now();
    for (const [url, value] of candidates) if (now - value.seenAt > V.MAX_AGE) candidates.delete(url);
    while (candidates.size > 24) candidates.delete(candidates.keys().next().value);
    lastReport = now;
    window.postMessage({ channel: V.CHANNEL, type: "report", report: {
      pageURL: baseURL(), title: document.title, candidates: [...candidates.values()], videos
    } }, "*");
  }
  function schedule() { if (enabled && pending === null) pending = setTimeout(report, 180); }
  function refresh() {
    if (!enabled) return;
    routeChanged();
    for (const root of roots) for (const node of root.querySelectorAll("*")) if (node.shadowRoot) observeRoot(node.shadowRoot);
    for (const entry of performance.getEntriesByType("resource"))
      if (entry.startTime >= routeStart) record(entry.name, "", "resource");
    // Direct download links are manual choices, never automatic prompts.
    for (const link of document.querySelectorAll("a[href]")) if (V.kind(V.networkURL(link.getAttribute("href"), baseURL()))) record(link.href, "", "link");
    for (const meta of document.querySelectorAll('meta[property="og:video"],meta[property="og:video:url"],meta[property="og:video:secure_url"]')) record(meta.content, "", "link");
    schedule();
  }
  observeRoot(document);
  // Retain observed shadow roots without exposing them to the isolated script.
  const attachShadow = Element.prototype.attachShadow;
  Element.prototype.attachShadow = function (...args) {
    const root = Reflect.apply(attachShadow, this, args);
    observeRoot(root);
    return root;
  };
  const originalFetch = window.fetch;
  if (originalFetch) window.fetch = function (...args) {
    const result = Reflect.apply(originalFetch, this, args);
    result.then(response => {
      if (enabled === false || !response.ok) return;
      try { record(response.url, response.headers.get("content-type") || "", "fetch"); } catch { /* Opaque response. */ }
    }).catch(() => {});
    return result;
  };
  const originalOpen = XMLHttpRequest.prototype.open;
  XMLHttpRequest.prototype.open = function (...args) {
    const result = Reflect.apply(originalOpen, this, args);
    xhrURLs.set(this, typeof args[1] === "string" ? args[1] : "");
    if (!xhrListeners.has(this)) {
      xhrListeners.add(this);
      this.addEventListener("load", () => {
        if (enabled === false || this.status < 200 || this.status >= 400) return;
        try { record(this.responseURL || xhrURLs.get(this), this.getResponseHeader("content-type") || "", "xhr"); } catch { /* Unavailable header. */ }
      });
    }
    return result;
  };
  try {
    new PerformanceObserver(list => {
      if (enabled === false) return;
      for (const entry of list.getEntries()) if (entry.startTime >= routeStart) record(entry.name, "", "resource");
    }).observe({ type: "resource", buffered: true });
  } catch { /* DOM and fetch/XHR detection remain available. */ }
  for (const method of ["pushState", "replaceState"]) {
    const original = history[method];
    history[method] = function (...args) { const result = Reflect.apply(original, this, args); routeChanged(); return result; };
  }
  for (const type of ["pointerdown", "touchstart", "keydown"])
    document.addEventListener(type, event => { if (event.isTrusted) lastInteraction = Date.now(); }, { capture: true, passive: true });
  window.addEventListener("popstate", routeChanged);
  window.addEventListener("hashchange", routeChanged);
  document.addEventListener("visibilitychange", schedule);
  window.addEventListener("pageshow", refresh);
  window.addEventListener("message", event => {
    const value = event.data;
    if (event.source !== window || !value || value.channel !== V.CHANNEL || value.type !== "control") return;
    if (typeof value.enabled === "boolean") {
      enabled = value.enabled;
      if (!enabled) { candidates.clear(); if (pending !== null) clearTimeout(pending); pending = null; }
      else refresh();
    }
    if (value.command === "refresh") refresh();
    if (value.command === "pause") for (const video of allVideos()) if (!video.paused) video.pause();
  });
})();
