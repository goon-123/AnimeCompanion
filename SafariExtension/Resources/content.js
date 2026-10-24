/* Isolated extension world: only this side can use browser APIs or show a prompt. */
(function () {
  "use strict";
  if (globalThis.__acVideoContentV1) return;
  Object.defineProperty(globalThis, "__acVideoContentV1", { value: true });
  const V = globalThis.ACVideo;
  const topFrame = window === window.top;
  let enabled = false;
  let state = null;
  let hostElement = null;
  let shadow = null;
  let displayedKey = "";
  let pickerOpen = false;
  let manualCandidateURL = "";
  const dismissed = new Set();
  const control = extra => window.postMessage({ channel: V.CHANNEL, type: "control", ...extra }, "*");
  const send = value => browser.runtime.sendMessage(value);
  const key = candidate => candidate.frameId + ":" + (candidate.playbackId || candidate.url);
  function remove() {
    hostElement?.remove(); hostElement = null; shadow = null; displayedKey = ""; pickerOpen = false;
  }
  function apply(next) {
    if (!next) return;
    const changed = enabled !== next.enabled;
    state = next; enabled = next.enabled;
    if (changed) control({ enabled });
    if (!enabled) { manualCandidateURL = ""; remove(); return; }
    if (!topFrame) return;
    const manual = next.candidates.find(x => x.url === manualCandidateURL);
    if (!manual && !next.options.autoPrompt) { remove(); return; }
    const candidate = manual || next.candidates.find(x => x.automatic && !dismissed.has(key(x)));
    if (!candidate) { remove(); return; }
    if (displayedKey === key(candidate) && hostElement?.isConnected) {
      // Keep the link's timestamp current without moving focus or rebuilding UI.
      if (!pickerOpen) { const link = shadow.querySelector("a[data-open]"); if (link) link.href = V.launchURL(candidate); }
      return;
    }
    show(candidate);
  }
  function element(tag, text, className) {
    const node = document.createElement(tag);
    if (text) node.textContent = text;
    if (className) node.className = className;
    return node;
  }
  function pause() {
    for (const video of document.querySelectorAll("video")) if (!video.paused) video.pause();
    control({ command: "pause" });
    send({ type: "ac-pause" }).catch(() => {});
  }
  function dismiss(candidate) { manualCandidateURL = ""; dismissed.add(key(candidate)); remove(); }
  function openLink(candidate, label = "Open in VidHub") {
    const link = element("a", label, "open");
    link.href = V.launchURL(candidate); link.dataset.open = "true";
    link.addEventListener("click", () => { pause(); manualCandidateURL = ""; dismissed.add(key(candidate)); setTimeout(remove, 100); });
    return link;
  }
  function show(candidate) {
    remove(); displayedKey = key(candidate);
    hostElement = document.createElement("div");
    hostElement.setAttribute("data-animecompanion-vidhub", "");
    hostElement.style.cssText = "all:initial!important;position:fixed!important;bottom:calc(16px + env(safe-area-inset-bottom))!important;right:16px!important;left:16px!important;max-width:390px!important;margin-left:auto!important;z-index:2147483647!important;color-scheme:dark!important;";
    shadow = hostElement.attachShadow({ mode: "closed" });
    const style = document.createElement("style");
    style.textContent = `
      :host{font:15px -apple-system,BlinkMacSystemFont,sans-serif;color:#f6f7fb;line-height:1.4}
      *{box-sizing:border-box}section{background:#151b29;border:1px solid #435066;border-radius:20px;padding:18px;box-shadow:0 12px 50px #0008}
      header{display:flex;justify-content:space-between;align-items:center;gap:12px}strong{font-size:17px}
      p{margin:8px 0 14px;color:#b8c5d8;overflow-wrap:anywhere}small{color:#9bb1cc;font-size:12px}
      button,a{font:inherit;cursor:pointer;-webkit-tap-highlight-color:transparent}button{color:#c0cede;background:none;border:0;padding:10px 0;min-height:44px}
      .close{font-size:22px;padding:0;min-width:44px;min-height:44px;margin:-8px -8px -8px 0}
      .open{display:block;text-align:center;padding:12px 16px;border-radius:12px;background:#bce5fa;color:#102435;font-weight:650;text-decoration:none;min-height:46px}
      footer{display:flex;justify-content:space-between;gap:16px;margin:4px 0 -8px}footer button{font-size:12px;text-align:left}
      .streams{max-height:210px;overflow:auto;margin:10px 0}.stream{margin:8px 0}.stream a{background:#26364b;color:#e0f3ff;font-size:13px;text-align:left}
      :focus-visible{outline:3px solid #fff;outline-offset:3px}@media(prefers-reduced-motion:reduce){*{scroll-behavior:auto}}
    `;
    shadow.append(style);
    const card = element("section"); card.setAttribute("role", "region"); card.setAttribute("aria-label", "Video detected – open in VidHub");
    const header = element("header");
    header.append(element("strong", "Watch in VidHub?"));
    const close = element("button", "×", "close"); close.type = "button"; close.setAttribute("aria-label", "Dismiss VidHub prompt");
    close.addEventListener("click", () => dismiss(candidate)); header.append(close); card.append(header);
    card.append(element("p", candidate.title));
    card.append(openLink(candidate));
    const footer = element("footer");
    const choose = element("button", "Choose stream"); choose.type = "button";
    choose.addEventListener("click", () => {
      const existing = card.querySelector(".streams");
      if (existing) { existing.remove(); pickerOpen = false; return; }
      pickerOpen = true;
      const list = element("div", "", "streams"); list.setAttribute("aria-label", "Detected streams");
      for (const item of state.candidates.slice(0, 12)) {
        const row = element("div", "", "stream");
        row.append(openLink(item, item.kind + " · " + item.host + " · " + item.filename)); list.append(row);
      }
      footer.before(list);
    });
    const disable = element("button", "Not on this site"); disable.type = "button";
    disable.addEventListener("click", () => {
      send({ type: "ac-set-options", siteEnabled: false }).then(() => { enabled = false; control({ enabled: false }); remove(); }).catch(() => { disable.textContent = "Try again"; });
    });
    footer.append(choose, disable); card.append(footer); shadow.append(card);
    (document.body || document.documentElement).append(hostElement);
  }
  function reload() {
    send({ type: "ac-get-state" }).then(next => { apply(next); control({ enabled: next.enabled, command: "refresh" }); }).catch(() => { enabled = false; remove(); });
  }
  window.addEventListener("message", event => {
    const value = event.data;
    if (event.source !== window || !enabled || !value || value.channel !== V.CHANNEL || value.type !== "report") return;
    const report = V.cleanReport(value.report);
    if (report) send({ type: "ac-report", report }).catch(() => {});
  });
  browser.runtime.onMessage.addListener(message => {
    if (message?.type === "ac-state") apply(message.state);
    if (message?.type === "ac-options-changed") reload();
    if (message?.type === "ac-refresh") { reload(); control({ command: "refresh" }); }
    if (message?.type === "ac-show-on-page" && topFrame && enabled && V.networkURL(message.candidate?.url)) {
      manualCandidateURL = message.candidate.url;
      show(message.candidate);
    }
    if (message?.type === "ac-pause-videos") { for (const video of document.querySelectorAll("video")) if (!video.paused) video.pause(); control({ command: "pause" }); }
    // Do not await reload's state request: the background serializes mutations.
    // An immediate acknowledgment prevents a settings-update/message deadlock.
    return Promise.resolve({ ok: true });
  });
  window.addEventListener("pageshow", reload);
  reload();
})();
