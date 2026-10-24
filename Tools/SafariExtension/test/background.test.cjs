const { test } = require("node:test");
const assert = require("node:assert/strict");
const { harness, report } = require("./helpers.cjs");
const sender = { tab: { id: 12, url: "https://watch.example/episode" }, frameId: 0 };

test("Safari's partial sender tab metadata still resolves the current top-level page", async () => {
  const h = harness();
  const result = await h.dispatch({ type: "ac-report", report: report() }, { tab: { id: 12 }, frameId: 3 });
  assert.equal(result.enabled, true);
  const state = await h.dispatch({ type: "ac-get-state", tabId: 12 });
  assert.equal(state.candidates.length, 1);
  assert.equal(state.candidates[0].frameId, 3);
});
test("stale sender URLs cannot split an SPA's reports across different pages", async () => {
  const h = harness({ getTab: id => ({ id, url: "https://watch.example/new-episode" }) });
  await h.dispatch({ type: "ac-report", report: report() }, sender);
  const state = await h.dispatch({ type: "ac-get-state", tabId: 12 });
  assert.equal(state.pageURL, "https://watch.example/new-episode");
  assert.equal(state.candidates.length, 1);
});
test("manual scan reinstalls a missing page observer even when the isolated script acknowledges", async () => {
  const h = harness({ onTabMessage: () => ({ ok: true }) });
  await h.dispatch({ type: "ac-scan", tabId: 12 });
  assert.equal(h.injected.length, 2);
  assert.equal(h.injected[0].world, "MAIN");
  assert.ok(h.injected[0].files.includes("observer.js"));
  assert.ok(h.delivered.filter(x => x.message.type === "ac-refresh").length >= 2);
});
test("a denied iframe does not prevent a manual scan from repairing the top page", async () => {
  const h = harness({ onInject: value => { if (value.target.allFrames) throw new Error("No frame permission"); } });
  await h.dispatch({ type: "ac-scan", tabId: 12 });
  assert.equal(h.injected.length, 3);
  assert.equal(h.injected[1].target.allFrames, undefined);
  assert.ok(h.injected[1].files.includes("observer.js"));
});
test("a session write failure cannot make a successful scan read stale stored data", async () => {
  const h = harness();
  h.browser.storage.session.set = async () => { throw new Error("Storage quota"); };
  await h.dispatch({ type: "ac-report", report: report() }, sender);
  assert.equal((await h.dispatch({ type: "ac-get-state", tabId: 12 })).candidates.length, 1);
});
test("navigation to an unsupported page cannot fall back to an old sender URL", async () => {
  const h = harness({ getTab: id => ({ id, url: "about:blank" }) });
  const result = await h.dispatch({ type: "ac-report", report: report() }, sender);
  assert.equal(result.enabled, false);
});
test("unavailable session storage falls back to bounded memory without persisting URLs", async () => {
  for (const config of [{ noSessionStorage: true }, { brokenSessionStorage: true }]) {
    const h = harness(config);
    await h.dispatch({ type: "ac-report", report: report() }, sender);
    assert.equal((await h.dispatch({ type: "ac-get-state", tabId: 12 })).candidates.length, 1);
    assert.equal(JSON.stringify(h.stores.local).includes("token="), false);
    await h.listeners.removed(12);
    assert.equal((await h.dispatch({ type: "ac-get-state", tabId: 12 })).candidates.length, 0);
  }
});
test("page handoff selects a currently detected link and targets the top frame", async () => {
  const h = harness();
  await h.dispatch({ type: "ac-report", report: report() }, sender);
  const state = await h.dispatch({ type: "ac-get-state", tabId: 12 });
  await h.dispatch({ type: "ac-show-on-page", tabId: 12, url: state.candidates[0].url });
  const sent = h.delivered.find(x => x.message.type === "ac-show-on-page");
  assert.equal(sent.options.frameId, 0);
  await assert.rejects(() => h.dispatch({ type: "ac-show-on-page", tabId: 12, url: "https://unseen.example/v.mp4" }));
});

test("detected URLs survive a nonpersistent background restart and never enter persistent preferences", async () => {
  const h = harness();
  await h.dispatch({ type: "ac-report", report: report() }, sender);
  const restarted = harness({ stores: h.stores });
  const state = await restarted.dispatch({ type: "ac-get-state", tabId: 12 });
  assert.equal(state.candidates.length, 1);
  assert.equal(state.candidates[0].position, 142.5);
  assert.equal(JSON.stringify(h.stores.local).includes("token="), false);
  assert.equal(JSON.stringify(h.stores.session).includes("token="), true);
});
test("concurrent reports from different frames do not overwrite each other", async () => {
  const h = harness();
  await Promise.all([0, 3, 7].map(frameId => h.dispatch({ type: "ac-report", report: report({ candidates: [{ url: `https://cdn.example/${frameId}.mp4`, source: "fetch" }] }) }, { ...sender, frameId })));
  const state = await h.dispatch({ type: "ac-get-state", tabId: 12 });
  assert.equal(state.candidates.length, 3);
});
test("site exclusion clears private links, survives restart, and can be undone", async () => {
  const h = harness();
  await h.dispatch({ type: "ac-report", report: report() }, sender);
  await h.dispatch({ type: "ac-set-options", tabId: 12, siteEnabled: false });
  const restarted = harness({ stores: h.stores });
  assert.equal((await restarted.dispatch({ type: "ac-get-state", tabId: 12 })).enabled, false);
  assert.equal(JSON.stringify(h.stores.session).includes("token="), false);
  await restarted.dispatch({ type: "ac-report", report: report() }, sender);
  assert.equal(JSON.stringify(h.stores.session).includes("token="), false);
  await restarted.dispatch({ type: "ac-set-options", tabId: 12, siteEnabled: true });
  assert.equal((await restarted.dispatch({ type: "ac-get-state", tabId: 12 })).enabled, true);
});
test("re-enabling global detection wakes existing tabs even after their private cache was cleared", async () => {
  const h = harness({ getTabs: () => [{ id: 12 }, { id: 99 }] });
  await h.dispatch({ type: "ac-report", report: report() }, sender);
  await h.dispatch({ type: "ac-set-options", tabId: 12, enabled: false });
  assert.equal(Object.keys(h.stores.session.safariVideoTabs).length, 0);
  h.delivered.length = 0;
  await h.dispatch({ type: "ac-set-options", tabId: 12, enabled: true });
  assert.equal(h.delivered.some(x => x.id === 99 && x.message.type === "ac-options-changed"), true);
});
test("new pages, reloads, and closed tabs cannot reuse an earlier page's links", async () => {
  let pageURL = sender.tab.url;
  const h = harness({ getTab: id => ({ id, url: pageURL }) });
  await h.dispatch({ type: "ac-report", report: report() }, sender);
  pageURL = "https://watch.example/different";
  assert.equal((await h.dispatch({ type: "ac-get-state", tabId: 12 })).candidates.length, 0);
  await h.listeners.updated(12, { status: "loading" });
  assert.equal(JSON.stringify(h.stores.session).includes("token="), false);
  await h.dispatch({ type: "ac-report", report: report() }, sender);
  await h.listeners.removed(12);
  assert.equal(JSON.stringify(h.stores.session).includes("token="), false);
});
test("a content script cannot report into an arbitrary tab or impersonate another extension", async () => {
  const h = harness();
  await h.dispatch({ type: "ac-report", tabId: 99, report: report() }, sender);
  assert.equal(Object.keys(h.stores.session.safariVideoTabs).join(), "12");
  await h.dispatch({ type: "ac-report", report: report() }, { ...sender, id: "other-extension" });
  assert.equal(Object.keys(h.stores.session.safariVideoTabs).length, 1);
});
test("private session cache stays bounded across many tabs and long signed URLs", async () => {
  const h = harness();
  for (let id = 1; id <= 20; id++) {
    const candidates = Array.from({ length: 24 }, (_, n) => ({ url: `https://cdn.example/${n}.mp4?token=` + "x".repeat(15000), source: "fetch" }));
    await h.dispatch({ type: "ac-report", report: report({ candidates }) }, { ...sender, tab: { ...sender.tab, id } });
  }
  assert.ok(Buffer.byteLength(JSON.stringify(h.stores.session)) < 1500100);
  assert.ok(Object.keys(h.stores.session.safariVideoTabs).length <= 12);
});
