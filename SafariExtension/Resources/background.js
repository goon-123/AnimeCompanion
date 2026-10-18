/* Nonpersistent Safari background: settings persist, private URLs are session-only. */
"use strict";
const Video = globalThis.ACVideo;
const CACHE_KEY = "safariVideoTabs";
const OPTIONS_KEY = "safariVideoOptions";
let work = Promise.resolve();
function serial(task) {
  const next = work.then(task, task);
  work = next.catch(() => {});
  return next;
}
async function settings() { return Video.options((await browser.storage.local.get(OPTIONS_KEY))[OPTIONS_KEY]); }
async function cache() { return (await browser.storage.session.get(CACHE_KEY))[CACHE_KEY] || {}; }
async function saveCache(tabs) {
  const ordered = Object.keys(tabs).sort((a, b) => tabs[b].updatedAt - tabs[a].updatedAt);
  for (const id of ordered.slice(12)) delete tabs[id];
  // Safari's storage is bounded; a large signed URL must not exhaust it.
  while (new TextEncoder().encode(JSON.stringify(tabs)).length > 1500000) {
    const oldest = Object.keys(tabs).sort((a, b) => tabs[a].updatedAt - tabs[b].updatedAt)[0];
    if (!oldest) break;
    delete tabs[oldest];
  }
  await browser.storage.session.set({ [CACHE_KEY]: tabs });
}
function tabID(message, sender) {
  const id = sender.tab?.id ?? message.tabId;
  if (!Number.isInteger(id) || id < 0) throw new Error("Open a website in Safari first.");
  return id;
}
async function currentURL(id, sender = {}) {
  const tab = sender.tab?.id === id ? sender.tab : await browser.tabs.get(id);
  return Video.networkURL(tab.url) || "";
}
async function snapshot(id, sender = {}) {
  const prefs = await settings();
  const tabs = await cache();
  const pageURL = await currentURL(id, sender);
  const entry = tabs[id];
  return Video.state(entry?.pageURL === pageURL ? entry : { pageURL }, prefs);
}
async function notify(id, state) {
  await Promise.allSettled([
    browser.tabs.sendMessage(id, { type: "ac-state", state }, { frameId: 0 }),
    browser.runtime.sendMessage({ type: "ac-state", tabId: id, state })
  ]);
}
async function receiveReport(message, sender) {
  if (!sender.tab || !Number.isInteger(sender.frameId)) return;
  const id = tabID(message, sender);
  const pageURL = await currentURL(id, sender);
  const prefs = await settings();
  if (!Video.allowed(pageURL, prefs)) return { enabled: false };
  const report = Video.cleanReport(message.report);
  if (!report) return;
  const tabs = await cache();
  const tab = tabs[id]?.pageURL === pageURL ? tabs[id] : { pageURL, frames: {} };
  tab.frames[sender.frameId] = report;
  const frames = Object.keys(tab.frames).sort((a, b) => tab.frames[b].updatedAt - tab.frames[a].updatedAt);
  for (const frame of frames.slice(8)) delete tab.frames[frame];
  tab.updatedAt = Date.now(); tabs[id] = tab;
  await saveCache(tabs);
  await notify(id, Video.state(tab, prefs));
  return { enabled: true };
}
async function scan(id) {
  try { await browser.tabs.sendMessage(id, { type: "ac-refresh" }); }
  catch {
    // The toolbar may grant access after the page has already loaded. Install
    // both worlds on demand; declarative scripts handle subsequent pages.
    const target = { tabId: id, allFrames: true };
    await browser.scripting.executeScript({ target, world: "MAIN", files: ["core.js", "observer.js"] });
    await browser.scripting.executeScript({ target, files: ["core.js", "content.js"] });
  }
}
async function updateOptions(message, sender) {
  const prefs = await settings();
  if (typeof message.enabled === "boolean") prefs.enabled = message.enabled;
  if (typeof message.autoPrompt === "boolean") prefs.autoPrompt = message.autoPrompt;
  if (message.resetSites === true) prefs.disabledHosts = [];
  if (typeof message.siteEnabled === "boolean") {
    const name = Video.host(await currentURL(tabID(message, sender), sender));
    if (name) prefs.disabledHosts = message.siteEnabled ? prefs.disabledHosts.filter(x => x !== name) : [...new Set([...prefs.disabledHosts, name])];
  }
  await browser.storage.local.set({ [OPTIONS_KEY]: prefs });
  const tabs = await cache();
  const ids = new Set(Object.keys(tabs).map(Number));
  if (Number.isInteger(sender.tab?.id ?? message.tabId)) ids.add(sender.tab?.id ?? message.tabId);
  for (const id of ids) if (tabs[id] && !Video.allowed(tabs[id].pageURL, prefs)) delete tabs[id];
  await saveCache(tabs);
  for (const id of ids) {
    await browser.tabs.sendMessage(id, { type: "ac-options-changed" }).catch(() => {});
    try { await notify(id, await snapshot(id)); } catch { /* A closed tab is already gone. */ }
  }
  return prefs;
}
browser.runtime.onMessage.addListener((message, sender) => {
  if (!message || typeof message !== "object" || (sender.id && sender.id !== browser.runtime.id)) return;
  switch (message.type) {
    case "ac-report": return serial(() => receiveReport(message, sender));
    case "ac-get-state": return serial(() => snapshot(tabID(message, sender), sender));
    case "ac-set-options": return serial(() => updateOptions(message, sender));
    case "ac-scan": return scan(tabID(message, sender)).then(() => ({ ok: true }));
    case "ac-pause": return browser.tabs.sendMessage(tabID(message, sender), { type: "ac-pause-videos" }).catch(() => {});
    default: return undefined;
  }
});
browser.tabs.onRemoved.addListener(id => serial(async () => {
  const tabs = await cache(); delete tabs[id]; await saveCache(tabs);
}));
browser.tabs.onUpdated.addListener((id, change) => {
  if (change.status !== "loading" && !change.url) return;
  return serial(async () => {
    const tabs = await cache(); delete tabs[id]; await saveCache(tabs);
    try { await notify(id, await snapshot(id)); } catch { /* The tab may close during navigation. */ }
  });
});
