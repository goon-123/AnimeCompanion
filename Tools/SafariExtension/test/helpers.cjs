const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");
const resources = path.resolve(__dirname, "../../../SafariExtension/Resources");
const script = name => fs.readFileSync(path.join(resources, name), "utf8");
function harness(config = {}) {
  const stores = config.stores || { local: {}, session: {} };
  const listeners = {};
  const delivered = [];
  const injected = [];
  const event = name => ({ addListener(fn) { listeners[name] = fn; } });
  const storage = name => ({
    async get(key) { return structuredClone(key ? { [key]: stores[name][key] } : stores[name]); },
    async set(value) { Object.assign(stores[name], structuredClone(value)); }
  });
  const browser = {
    storage: { local: storage("local"), session: storage("session") },
    runtime: { id: "animecompanion-safari-test", onMessage: event("message"), async sendMessage(message) { return config.onRuntimeMessage?.(message); } },
    tabs: {
      onRemoved: event("removed"), onUpdated: event("updated"),
      async get(id) { return config.getTab?.(id) || { id, url: "https://watch.example/episode" }; },
      async sendMessage(id, message, options) { delivered.push({ id, message, options }); return config.onTabMessage?.(id, message, options); }
    },
    scripting: { async executeScript(value) { injected.push(value); } }
  };
  const context = vm.createContext({ browser, URL, TextEncoder, console, Date, Promise });
  vm.runInContext(script("core.js"), context);
  vm.runInContext(script("background.js"), context);
  return {
    stores, browser, delivered, injected, listeners,
    async dispatch(message, sender = {}) { return listeners.message(message, { id: browser.runtime.id, ...sender }); }
  };
}
function report(overrides = {}) {
  const now = Date.now();
  return {
    pageURL: "https://watch.example/episode", title: "Episode 4",
    candidates: [{ url: "https://cdn.example/master.m3u8?token=a%2Bb&part=1", source: "fetch", seenAt: now }],
    videos: [{ id: "main:1", url: null, position: 142.5, playing: true, visible: true, area: 180000, muted: false, startedAt: now, ...overrides.video }],
    ...overrides
  };
}
module.exports = { resources, script, harness, report };
