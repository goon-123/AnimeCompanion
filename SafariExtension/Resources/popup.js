"use strict";
const V = globalThis.ACVideo;
const $ = id => document.getElementById(id);
let tabId = null;
let current = null;
let disposed = false;
let layoutKey = "";
const send = message => browser.runtime.sendMessage({ ...message, tabId });
function error(message) { $("error").hidden = !message; $("error").textContent = message || ""; }
function render(state) {
  if (!state || disposed) return;
  current = state;
  $("site").textContent = state.host || "Open a website in Safari to find videos.";
  $("enabled").checked = state.options.enabled;
  $("prompts").checked = state.options.autoPrompt;
  $("prompts").disabled = !state.options.enabled;
  $("handoff").value = state.options.handoff;
  $("test-vidhub").href = V.launchURL({ url: V.SAMPLE_URL }, state.options.handoff);
  $("site-enabled").checked = !state.options.disabledHosts.includes(state.host);
  $("site-enabled").disabled = !state.host || !state.options.enabled;
  $("scan").disabled = !state.enabled;
  $("reset").disabled = state.options.disabledHosts.length === 0;
  $("status").textContent = !state.host ? "Open a website in Safari to find videos." : !state.options.enabled ? "Video detection is turned off." : !state.enabled ? "Detection is off for this website." : state.candidates.length ? `${state.candidates.length} stream${state.candidates.length === 1 ? "" : "s"} found` : "No playable link found yet. Start a video, then scan again.";
  const nextKey = JSON.stringify([state.options.handoff, state.candidates.map(x => [x.url, x.title, x.kind, x.playing, x.filename])]);
  if (layoutKey === nextKey) {
    for (const link of $("streams").querySelectorAll("a[data-stream]")) {
      const candidate = state.candidates.find(x => x.url === link.dataset.stream);
      if (candidate) link.href = V.launchURL(candidate, link.dataset.method);
    }
    return;
  }
  layoutKey = nextKey;
  const fragment = document.createDocumentFragment();
  for (const candidate of state.candidates) {
    const row = document.createElement("article"); row.className = "stream";
    const title = document.createElement("h3"); title.textContent = candidate.title;
    const meta = document.createElement("p");
    const badge = document.createElement("span"); badge.className = "badge"; badge.textContent = candidate.kind + (candidate.playing ? " · Playing" : "");
    meta.append(badge, document.createTextNode(" · " + candidate.host));
    const name = document.createElement("p"); name.textContent = candidate.filename;
    const link = document.createElement("a"); link.className = "open"; link.href = V.launchURL(candidate, state.options.handoff);
    link.dataset.stream = candidate.url; link.dataset.method = state.options.handoff;
    link.textContent = "Open in VidHub";
    link.addEventListener("click", () => { send({ type: "ac-pause" }).catch(() => {}); });
    const alternative = document.createElement("a"); alternative.className = "alternate";
    alternative.dataset.stream = candidate.url; alternative.dataset.method = state.options.handoff === "resume" ? "compatible" : "resume";
    alternative.href = V.launchURL(candidate, alternative.dataset.method);
    alternative.textContent = alternative.dataset.method === "compatible" ? "Try compatibility opener" : "Try resume opener";
    alternative.addEventListener("click", () => { send({ type: "ac-pause" }).catch(() => {}); });
    const copy = document.createElement("button"); copy.className = "copy"; copy.textContent = "Copy stream link";
    copy.addEventListener("click", async () => {
      try { await V.copyURL(candidate.url); copy.textContent = "Stream link copied"; error(""); }
      catch { error("Copy failed. Allow clipboard access, or try Copy link from the webpage prompt."); }
    });
    const onPage = document.createElement("button"); onPage.className = "on-page";
    onPage.textContent = "Open from webpage";
    onPage.addEventListener("click", async () => {
      try {
        await send({ type: "ac-show-on-page", url: candidate.url });
        window.close();
      } catch { error("Allow access to the page, scan again, then try Open from webpage."); }
    });
    row.append(title, meta, name, link, alternative, copy, onPage); fragment.append(row);
  }
  $("streams").replaceChildren(fragment);
}
async function load() { if (Number.isInteger(tabId)) render(await send({ type: "ac-get-state" })); }
async function scan() {
  error(""); $("scan").disabled = true;
  try { await send({ type: "ac-scan" }); setTimeout(() => load().catch(() => {}), 450); }
  catch { error("Allow this extension on the website, reload the page, and start the video again."); }
  finally { $("scan").disabled = !current?.enabled; }
}
async function update(value) {
  error("");
  try { await send({ type: "ac-set-options", ...value }); await load(); if (current?.enabled) await scan(); }
  catch { error("Could not save the preference. Try reopening the extension."); }
}
$("enabled").addEventListener("change", () => update({ enabled: $("enabled").checked }));
$("prompts").addEventListener("change", () => update({ autoPrompt: $("prompts").checked }));
$("handoff").addEventListener("change", () => update({ handoff: $("handoff").value }));
$("site-enabled").addEventListener("change", () => update({ siteEnabled: $("site-enabled").checked }));
$("reset").addEventListener("click", () => update({ resetSites: true }));
$("scan").addEventListener("click", scan);
browser.runtime.onMessage.addListener(message => { if (message?.type === "ac-state" && message.tabId === tabId) render(message.state); });
window.addEventListener("pagehide", () => { disposed = true; });
(async () => {
  try {
    let [tab] = await browser.tabs.query({ active: true, currentWindow: true });
    if (tab && !V.networkURL(tab.url)) {
      try { tab = await browser.tabs.get(tab.id); } catch { /* Render the access instructions below. */ }
    }
    if (!tab || !V.networkURL(tab.url)) {
      $("status").textContent = "Open an HTTP or HTTPS website in Safari to find videos.";
      for (const id of ["scan", "site-enabled"]) $(id).disabled = true;
      // Global settings still work from Safari's start page.
      const saved = await browser.storage.local.get("safariVideoOptions");
      const prefs = V.options(saved.safariVideoOptions);
      render(V.state(null, prefs));
      return;
    }
    tabId = tab.id; await load(); if (current?.enabled) await scan();
  } catch { error("Allow website access in Safari, then reopen this extension."); }
})();
