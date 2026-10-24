const { test, before, after } = require("node:test");
const assert = require("node:assert/strict");
const http = require("node:http");
const fs = require("node:fs");
const path = require("node:path");
const { webkit } = require("playwright");
const { harness, script, resources } = require("./helpers.cjs");
let browser;
let server;
let embedServer;
let origin;
let embedOrigin;
const artifacts = path.resolve(__dirname, "../../../build/safari-browser");
const fixture = fs.readFileSync(path.join(__dirname, "fixtures/video.webm"));
const pageHTML = (mode = "direct") => `<!doctype html><html><head><meta charset="utf-8"><title>Safari video test</title>
  <style>body{font:16px -apple-system,sans-serif;background:#0e1420;color:#fff;margin:24px}video,iframe{width:320px;height:180px;border:0}button{font:inherit;padding:14px;margin:12px 0}</style></head><body>
  <h1>Watch your way</h1><p>A local test video.</p>
  ${mode === "parent" ? `<iframe src="${embedOrigin}/embedded"></iframe>` : `<video id="video" muted playsinline ${mode === "shadow" ? "" : 'src="/video.webm?token=a%2Bb&part=1"'}></video><br><button id="play">Play video</button>`}
  <script>
    const video=document.querySelector('video');
    if(video)document.querySelector('#play').onclick=()=>video.play();
  </script></body></html>`;
function serve(request, response) {
  const url = new URL(request.url, "http://localhost");
  response.setHeader("Access-Control-Allow-Origin", "*");
  if (url.pathname === "/video.webm") {
    response.writeHead(200, { "Content-Type": "video/webm", "Content-Length": fixture.length }); response.end(fixture); return;
  }
  if (url.pathname === "/stream") {
    response.writeHead(200, { "Content-Type": "application/vnd.apple.mpegurl" }); response.end("#EXTM3U\n#EXT-X-VERSION:3\n"); return;
  }
  if (["/popup.html", "/popup.js", "/core.js", "/popup.css"].includes(url.pathname)) {
    response.writeHead(200, { "Content-Type": url.pathname.endsWith(".js") ? "application/javascript" : url.pathname.endsWith(".css") ? "text/css" : "text/html" });
    response.end(fs.readFileSync(path.join(resources, url.pathname.slice(1)))); return;
  }
  response.writeHead(200, { "Content-Type": "text/html" }); response.end(pageHTML(url.pathname === "/parent" ? "parent" : "direct"));
}
const listen = value => new Promise(resolve => value.listen(0, "127.0.0.1", resolve));
before(async () => {
  fs.mkdirSync(artifacts, { recursive: true });
  server = http.createServer(serve); embedServer = http.createServer(serve);
  await listen(server); await listen(embedServer);
  origin = "http://127.0.0.1:" + server.address().port;
  embedOrigin = "http://127.0.0.1:" + embedServer.address().port;
  browser = await webkit.launch({ headless: true });
});
after(async () => { await browser?.close(); server?.close(); embedServer?.close(); });
async function setup(route = "/direct", config = {}) {
  const context = await browser.newContext({ viewport: { width: 390, height: 844 } });
  const page = await context.newPage();
  const frameIDs = new Map();
  const errors = [];
  let nextFrame = 1;
  page.on("pageerror", value => errors.push(value.message));
  const h = harness({
    getTab: id => ({ id, url: page.url() }),
    async onInject(value) {
      for (const frame of page.frames().filter(frame => !frame.isDetached())) {
        for (const name of value.files) await frame.evaluate(code => { (0, eval)(code); }, script(name));
      }
    },
    async onTabMessage(id, message, options) {
      const targets = page.frames().filter(frame => !frame.isDetached() && (options?.frameId === undefined || (frame === page.mainFrame() ? 0 : frameIDs.get(frame)) === options.frameId));
      await Promise.all(targets.map(frame => frame.evaluate(value => { for (const fn of globalThis.__acListeners || []) fn(value); }, message).catch(() => {})));
      return { ok: true };
    }
  });
  await context.exposeBinding("extensionSend", async ({ frame }, message) => {
    if (!frameIDs.has(frame)) frameIDs.set(frame, frame === page.mainFrame() ? 0 : nextFrame++);
    return h.dispatch(message, { tab: { id: 1, url: page.url() }, frameId: frameIDs.get(frame), url: frame.url() });
  });
  const stub = `
    globalThis.__acListeners=[];
    globalThis.browser={runtime:{sendMessage:value=>window.extensionSend(value),onMessage:{addListener:fn=>__acListeners.push(fn)}}};
  `;
  await context.addInitScript({ content: stub + script("core.js") + (config.observer === false ? "" : script("observer.js")) + script("content.js") });
  await page.goto(origin + route);
  return { context, page, h, errors, async state() { return h.dispatch({ type: "ac-get-state", tabId: 1 }); } };
}
async function waitFor(check, message) {
  const limit = Date.now() + 12000;
  while (Date.now() < limit) { if (await check()) return; await new Promise(resolve => setTimeout(resolve, 100)); }
  throw new Error(message);
}
async function promptLink(page) {
  // The product uses a closed shadow tree. Browser tests locate the actual
  // accessible control through WebKit's accessibility tree via a test-only
  // pre-install attachShadow wrapper, below, when its internal link is needed.
  return page.evaluate(() => globalThis.__acTestRoots?.find(root => root.host.hasAttribute("data-animecompanion-vidhub"))?.querySelector("a[data-open]")?.href);
}
test("a real playing video produces one prompt, carries the current timestamp, and dismisses without repeated prompts", async () => {
  const t = await setup();
  try {
    // A root wrapper added before UI creation permits test inspection without
    // weakening the extension's closed shadow root in production.
    await t.page.evaluate(() => {
      const original = Element.prototype.attachShadow; globalThis.__acTestRoots = [];
      Element.prototype.attachShadow = function (...args) { const root = Reflect.apply(original, this, args); __acTestRoots.push(root); return root; };
    });
    await t.page.click("#play");
    await waitFor(async () => (await t.state()).candidates.some(x => x.automatic), "Playing video was not recognized");
    await t.page.waitForSelector("[data-animecompanion-vidhub]");
    await t.page.evaluate(() => { document.querySelector("video").currentTime = 6; });
    await waitFor(async () => Number(new URL((await promptLink(t.page)) || "https://example.com").searchParams.get("position")) >= 6, "Prompt did not retain the current position");
    const link = new URL(await promptLink(t.page));
    assert.equal(link.protocol, "open-vidhub:");
    assert.equal(new URL(link.searchParams.get("url")).searchParams.get("token"), "a+b");
    assert.equal(await t.page.locator("[data-animecompanion-vidhub]").count(), 1);
    await t.page.screenshot({ path: path.join(artifacts, "iphone-video-prompt.png") });
    await t.page.evaluate(() => __acTestRoots.find(root => root.host.isConnected && root.host.hasAttribute("data-animecompanion-vidhub")).querySelector("button.close").click());
    await t.page.waitForSelector("[data-animecompanion-vidhub]", { state: "detached" });
    await new Promise(resolve => setTimeout(resolve, 2000));
    assert.equal(await t.page.locator("[data-animecompanion-vidhub]").count(), 0);
    assert.deepEqual(t.errors, []);
  } finally { await t.context.close(); }
});
test("manual scan repairs an absent observer even though a content script acknowledges messages", async () => {
  const t = await setup("/direct", { observer: false });
  try {
    await t.page.click("#play");
    assert.equal((await t.state()).candidates.length, 0);
    await t.h.dispatch({ type: "ac-scan", tabId: 1 });
    await waitFor(async () => (await t.state()).candidates.some(x => x.playing), "Scan did not restore the missing page observer");
    assert.deepEqual(t.errors, []);
  } finally { await t.context.close(); }
});
test("manual-only mode can hand an embedded stream to a real link on the parent webpage", async () => {
  const t = await setup("/parent");
  try {
    const frame = t.page.frames().find(frame => frame.url().startsWith(embedOrigin));
    await frame.click("#play");
    await waitFor(async () => (await t.state()).candidates.some(x => x.playing), "No embedded stream");
    await t.h.dispatch({ type: "ac-set-options", tabId: 1, autoPrompt: false });
    await t.page.waitForSelector("[data-animecompanion-vidhub]", { state: "detached" });
    await t.page.evaluate(() => {
      const original = Element.prototype.attachShadow; globalThis.__acTestRoots = [];
      Element.prototype.attachShadow = function (...args) { const root = Reflect.apply(original, this, args); __acTestRoots.push(root); return root; };
    });
    const candidate = (await t.state()).candidates[0];
    await t.h.dispatch({ type: "ac-show-on-page", tabId: 1, url: candidate.url });
    await t.page.waitForSelector("[data-animecompanion-vidhub]");
    const url = new URL(await promptLink(t.page));
    assert.equal(url.searchParams.get("url"), candidate.url);
    assert.equal(url.protocol, "open-vidhub:");
    assert.equal((await t.state()).options.autoPrompt, false);
    await t.page.evaluate(() => {
      const link = __acTestRoots.find(root => root.host.isConnected).querySelector("a[data-open]");
      link.addEventListener("click", event => event.preventDefault()); link.click();
    });
    await frame.waitForFunction(() => document.querySelector("video").paused);
    assert.deepEqual(t.errors, []);
  } finally { await t.context.close(); }
});
test("embedded videos report across origins and share a single prompt in the parent page", async () => {
  const t = await setup("/parent");
  try {
    const frame = t.page.frames().find(frame => frame.url().startsWith(embedOrigin));
    assert.ok(frame);
    await frame.click("#play");
    await waitFor(async () => (await t.state()).candidates.some(x => x.automatic && x.frameId > 0), "Embedded video did not reach the parent");
    await t.page.waitForSelector("[data-animecompanion-vidhub]");
    assert.equal(await frame.locator("[data-animecompanion-vidhub]").count(), 0);
    await t.page.screenshot({ path: path.join(artifacts, "embedded-video-prompt.png") });
    await t.h.dispatch({ type: "ac-set-options", tabId: 1, siteEnabled: false });
    await t.page.waitForSelector("[data-animecompanion-vidhub]", { state: "detached" });
    assert.equal((await t.state()).enabled, false);
    assert.equal(JSON.stringify(t.h.stores.local).includes("token="), false);
    assert.deepEqual(t.errors, []);
  } finally { await t.context.close(); }
});
test("extensionless HLS is discovered without consuming the fetch response and old SPA links disappear", async () => {
  const t = await setup();
  try {
    const body = await t.page.evaluate(async () => (await fetch("/stream?token=signed" )).text());
    assert.ok(body.startsWith("#EXTM3U"));
    await waitFor(async () => (await t.state()).candidates.some(x => x.kind === "HLS"), "Extensionless HLS response was not detected");
    await t.page.evaluate(() => {
      document.querySelector("video").remove();
      history.pushState({}, "", "/different-video");
    });
    await waitFor(async () => (await t.state()).candidates.length === 0, "An earlier SPA route retained private stream URLs");
    assert.deepEqual(t.errors, []);
  } finally { await t.context.close(); }
});
test("page text is rendered as text and manually selected links cannot execute HTML", async () => {
  const t = await setup();
  try {
    await t.page.evaluate(() => { document.title = '<img src=x onerror="window.injected=true">'; });
    await t.page.click("#play");
    await t.page.waitForSelector("[data-animecompanion-vidhub]");
    assert.equal(await t.page.evaluate(() => Boolean(window.injected)), false);
    assert.deepEqual(t.errors, []);
  } finally { await t.context.close(); }
});
test("an explicit Open tap pauses Safari's video and produces a valid VidHub handoff", async () => {
  const t = await setup();
  try {
    await t.page.evaluate(() => {
      const original = Element.prototype.attachShadow; globalThis.__acTestRoots = [];
      Element.prototype.attachShadow = function (...args) { const root = Reflect.apply(original, this, args); __acTestRoots.push(root); return root; };
    });
    await t.page.click("#play");
    await t.page.waitForSelector("[data-animecompanion-vidhub]");
    const link = await t.page.evaluate(() => {
      const root = __acTestRoots.find(root => root.host.hasAttribute("data-animecompanion-vidhub"));
      const link = root.querySelector("a[data-open]");
      link.addEventListener("click", event => event.preventDefault());
      link.click(); return link.href;
    });
    assert.equal(new URL(link).protocol, "open-vidhub:");
    await t.page.waitForFunction(() => document.querySelector("video").paused);
    await t.page.waitForSelector("[data-animecompanion-vidhub]", { state: "detached" });
    assert.deepEqual(t.errors, []);
  } finally { await t.context.close(); }
});
test("the toolbar stream picker saves manual-only mode and site exclusions", async () => {
  const t = await setup();
  const popupContext = await browser.newContext({ viewport: { width: 390, height: 844 } });
  try {
    await t.page.click("#play");
    await waitFor(async () => (await t.state()).candidates.length > 0, "No stream for the picker");
    await popupContext.exposeBinding("popupSend", (_, value) => t.h.dispatch(value));
    await popupContext.exposeBinding("popupGet", (_, key) => t.h.browser.storage.local.get(key));
    await popupContext.addInitScript({ content: `globalThis.browser={
      runtime:{sendMessage:value=>window.popupSend(value),onMessage:{addListener(){}}},
      tabs:{query:async()=>[{id:1,url:${JSON.stringify(origin + "/direct")}}]},
      storage:{local:{get:key=>window.popupGet(key)}}
    };` });
    const popup = await popupContext.newPage();
    await popup.goto(origin + "/popup.html");
    await popup.waitForSelector("a.open");
    assert.equal(new URL(await popup.locator("a.open").first().getAttribute("href")).protocol, "open-vidhub:");
    await popup.locator("#prompts").uncheck();
    await waitFor(async () => (await t.state()).options.autoPrompt === false, "Manual-only preference did not save");
    await popup.screenshot({ path: path.join(artifacts, "stream-picker.png") });
    await popup.locator("#site-enabled").uncheck();
    await waitFor(async () => (await t.state()).enabled === false, "Site exclusion did not save");
    assert.equal(JSON.stringify(t.h.stores.local).includes("token="), false);
  } finally { await popupContext.close(); await t.context.close(); }
});
