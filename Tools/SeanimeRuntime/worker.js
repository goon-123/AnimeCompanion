import ts from "typescript";
import { DOMParser } from "linkedom";

// The compiler and compatibility code are bundled with the signed app. Only a
// reviewed provider snapshot is evaluated, in a disposable Web Worker. No app
// credentials, filesystem, tracking store, or debrid key enter this worker.
const send = self.postMessage.bind(self);
const pending = new Map();
let nextID = 0, errorCount = 0, networkCount = 0, networkBytes = 0;
let preferences = {}, failedNetwork = false, unsupported = false, httpFailures = 0;

function unsupportedAPI() { unsupported = true; throw new Error("Unsupported runtime API"); }
globalThis.console = { log() {}, info() {}, debug() {}, warn() {}, error() { errorCount++; } };
globalThis.importScripts = unsupportedAPI;
globalThis.WebSocket = unsupportedAPI;
globalThis.EventSource = unsupportedAPI;
globalThis.XMLHttpRequest = unsupportedAPI;
globalThis.Worker = unsupportedAPI;
globalThis.$getUserPreference = name => preferences[String(name)] ?? "";
globalThis.$clone = value => JSON.parse(JSON.stringify(value));
globalThis.$toString = value => new TextDecoder().decode(new Uint8Array(value));
globalThis.$toBytes = value => new TextEncoder().encode(String(value));
globalThis.ChromeDP = new Proxy({}, { get: () => unsupportedAPI });
globalThis.$scannerUtils = new Proxy({}, { get: () => unsupportedAPI });
globalThis.CryptoJS = new Proxy({}, { get: () => unsupportedAPI });
globalThis.$habari = { parse: parseFilename };

export function parseFilename(value) {
  // Conservative display hints, not Seanime's complete Habari matching engine.
  // No automatic season/title/file selection is based on this compatibility shim.
  const name = String(value);
  const match = name.match(/S(\d{1,2})E(\d{1,4}(?:\.\d+)?)/i) || name.match(/(?:\s-\s|\bE(?:P)?\s*)(\d{1,4}(?:\.\d+)?)(?:v\d+)?\b/i);
  const season = name.match(/\bS(?:eason\s*)?0*(\d{1,2})\b/i);
  const episode = match ? [match[2] ?? match[1]] : [];
  const title = name.replace(/^\[[^\]]+\]\s*/, "").replace(/\s-\s\d+.*$/, "").replace(/\bS\d+E\d+.*$/i, "").replace(/\[[^\]]*\]/g, "").replace(/\.(mkv|mp4|avi|webm)$/i, "").trim();
  return { file_name: name, title, formatted_title: title, episode_number: episode,
    season_number: season ? [season[1]] : [], part_number: [], other_episode_number: [],
    video_resolution: name.match(/\b(2160p|1080p|720p|480p)\b/i)?.[1] ?? "",
    release_group: name.match(/^\[([^\]]+)\]/)?.[1] ?? "", language: [], audio_term: [], subtitles: [] };
}

export function loadDoc(html) {
  const doc = new DOMParser().parseFromString(String(html), "text/html");
  class Selection {
    constructor(nodes) { this.nodes = Array.from(nodes); this.length = this.nodes.length; }
    attr(key) { return this.nodes[0]?.getAttribute?.(key) ?? ""; }
    text() { return this.nodes.map(n => n.textContent ?? "").join(""); }
    html() { return this.nodes[0]?.innerHTML ?? ""; }
    first() { return new Selection(this.nodes.slice(0, 1)); }
    eq(index) { return new Selection(this.nodes.slice(index, index + 1)); }
    find(selector) { return new Selection(this.nodes.flatMap(n => Array.from(n.querySelectorAll(selector)))); }
    children(selector) { return new Selection(this.nodes.flatMap(n => Array.from(n.children ?? [])).filter(n => !selector || n.matches(selector))); }
    each(callback) { for (let i = 0; i < this.nodes.length; i++) if (callback(i, new Selection([this.nodes[i]])) === false) break; return this; }
    map(callback) { return this.nodes.map((n, i) => callback(i, new Selection([n]))); }
    filter(callback) { return new Selection(this.nodes.filter((n, i) => typeof callback === "string" ? n.matches(callback) : callback(i, new Selection([n])))); }
  }
  return (input) => input instanceof Selection ? input : typeof input === "string" ? new Selection(doc.querySelectorAll(input)) : new Selection(input ? [input] : []);
}
globalThis.LoadDoc = loadDoc;

globalThis.fetch = async (url, options = {}) => {
  if (String(options.method ?? "GET").toUpperCase() !== "GET" || options.body || options.headers) return unsupportedAPI();
  if (++networkCount > 24) { failedNetwork = true; throw new Error("Network request budget exceeded"); }
  const id = ++nextID;
  return new Promise((resolve, reject) => {
    pending.set(id, { resolve, reject });
    send({ kind: "fetch", id, url: String(url) });
  });
};

export async function runProvider(input) {
  preferences = input.preferences ?? {}; errorCount = 0; failedNetwork = false; unsupported = false;
  networkCount = 0; networkBytes = 0; httpFailures = 0;
  const compiled = ts.transpileModule(input.source, {
    reportDiagnostics: true,
    compilerOptions: { target: ts.ScriptTarget.ES2020, module: ts.ModuleKind.None, isolatedModules: true }
  });
  if (compiled.diagnostics?.some(d => d.category === ts.DiagnosticCategory.Error)) throw new Error("Invalid TypeScript");
  const Provider = new Function(compiled.outputText + "\n;return typeof Provider === 'function' ? Provider : null;")();
  if (!Provider) throw new Error("Missing Provider class");
  const provider = new Provider();
  const settings = typeof provider.getSettings === "function" ? await provider.getSettings() : {};
  if (settings.supportsAdult && !input.allowAdult) return { error: "adult" };
  if (input.method === "settings") return { settings };
  let value;
  if (input.method === "search") value = await provider.search(input.options);
  else if (input.method === "magnet") value = await provider.getTorrentMagnetLink(input.torrent);
  else throw new Error("Unsupported operation");
  if (failedNetwork || unsupported || ((errorCount > 0 || httpFailures > 0) && Array.isArray(value) && !value.length)) throw new Error("Provider failure");
  if (input.method === "search") {
    if (!Array.isArray(value) || value.length > 1000) throw new Error("Invalid result list");
    return { torrents: value, warnings: errorCount + httpFailures };
  }
  if (typeof value !== "string" || !value.startsWith("magnet:")) throw new Error("Invalid magnet");
  return { magnet: value };
}

self.onmessage = async ({ data }) => {
  if (data.kind === "response") {
    const item = pending.get(data.id); if (!item) return;
    pending.delete(data.id);
    if (data.error) { failedNetwork = true; item.reject(new Error("Provider network request failed")); return; }
    if (data.status < 200 || data.status >= 300) httpFailures++;
    networkBytes += String(data.text ?? "").length;
    if (networkBytes > 12_000_000) { failedNetwork = true; item.reject(new Error("Network response budget exceeded")); return; }
    item.resolve({ ok: data.status >= 200 && data.status < 300, status: data.status, statusText: String(data.status),
      // Seanime returns body values synchronously; await also accepts these values.
      text: () => data.text, json: () => JSON.parse(data.text), url: "", headers: {}, rawHeaders: {} });
    return;
  }
  if (data.kind !== "run") return;
  try { send({ kind: "result", result: await runProvider(data.input) }); }
  catch { send({ kind: "result", result: { error: "runtime" } }); }
};
