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
  const unique = nodes => [...new Set(nodes.filter(Boolean))];
  class Selection {
    constructor(nodes, previous = null) {
      this.nodes = unique(Array.from(nodes)); this.previous = previous;
      // Seanime specifies length(); numeric comparisons also work for providers
      // originally written against Cheerio's length property.
      this.length = () => this.nodes.length;
      this.length[Symbol.toPrimitive] = () => this.nodes.length;
    }
    wrap(nodes) { return new Selection(nodes, this); }
    attr(key) { return this.nodes[0]?.getAttribute?.(key) ?? ""; }
    attrs() { return Object.fromEntries(Array.from(this.nodes[0]?.attributes ?? []).map(a => [a.name, a.value])); }
    text() { return this.nodes.map(n => n.textContent ?? "").join(""); }
    html() { return this.nodes[0]?.innerHTML ?? ""; }
    first() { return this.wrap(this.nodes.slice(0, 1)); }
    last() { return this.wrap(this.nodes.slice(-1)); }
    eq(index) { const i = index < 0 ? this.nodes.length + index : index; return this.wrap(i < 0 ? [] : this.nodes.slice(i, i + 1)); }
    slice(start, end) { return this.wrap(this.nodes.slice(start, end)); }
    end() { return this.previous ?? new Selection([]); }
    find(selector) { return this.wrap(this.nodes.flatMap(n => Array.from(n.querySelectorAll?.(selector) ?? []))); }
    children(selector) { return this.wrap(this.nodes.flatMap(n => Array.from(n.children ?? [])).filter(n => !selector || n.matches(selector))); }
    contents() { return this.wrap(this.nodes.flatMap(n => Array.from(n.childNodes ?? []))); }
    contentsFiltered(selector) { return this.contents().filter(selector); }
    each(callback) { for (let i = 0; i < this.nodes.length; i++) if (callback(i, new Selection([this.nodes[i]], this)) === false) break; return this; }
    map(callback) { return this.nodes.map((n, i) => callback(i, new Selection([n], this))); }
    filter(callback) { return this.wrap(this.nodes.filter((n, i) => typeof callback === "string" ? n.matches?.(callback) : callback(i, new Selection([n], this)))); }
    not(callback) { return this.wrap(this.nodes.filter((n, i) => !(typeof callback === "string" ? n.matches?.(callback) : callback(i, new Selection([n], this))))); }
    is(selector) { return this.nodes.some((n,i) => typeof selector === "string" ? n.matches?.(selector) : selector(i,new Selection([n],this))); }
    has(selector) { return this.wrap(this.nodes.filter(n => n.querySelector?.(selector))); }
    parent(selector) { return this.wrap(this.nodes.map(n => n.parentElement).filter(n => n && (!selector || n.matches(selector)))); }
    closest(selector) { return this.wrap(this.nodes.map(n => selector ? n.closest?.(selector) : n.parentElement)); }
    traverse(direction, selector, until, first) {
      const result = [];
      for (const node of this.nodes) {
        let current = node[direction];
        while (current) {
          if (until && current.matches?.(until)) break;
          if (!selector || current.matches?.(selector)) result.push(current);
          if (first) break;
          current = current[direction];
        }
      }
      return this.wrap(result);
    }
    next(selector) { return this.traverse("nextElementSibling",selector,null,true); }
    prev(selector) { return this.traverse("previousElementSibling",selector,null,true); }
    nextAll(selector) { return this.traverse("nextElementSibling",selector,null,false); }
    prevAll(selector) { return this.traverse("previousElementSibling",selector,null,false); }
    nextUntil(until, selector) { return this.traverse("nextElementSibling",selector,until,false); }
    prevUntil(until, selector) { return this.traverse("previousElementSibling",selector,until,false); }
    parents(selector) { return this.traverse("parentElement",selector,null,false); }
    parentsUntil(until, selector) { return this.traverse("parentElement",selector,until,false); }
    siblings(selector) { const own = new Set(this.nodes); return this.parent().children(selector).filter((_, el) => !own.has(el.nodes[0])); }
    data(name) {
      if (name !== undefined) return this.attr("data-" + String(name).replace(/[A-Z]/g, c => "-" + c.toLowerCase()));
      return Object.fromEntries(Object.entries(this.attrs()).filter(([key]) => key.startsWith("data-")).map(([key,value]) => [key.slice(5).replace(/-([a-z])/g,(_,c)=>c.toUpperCase()),value]));
    }
    remove() { this.nodes.forEach(n => n.remove?.()); return this; }
  }
  const select = input => input instanceof Selection ? input : typeof input === "string" ? new Selection(doc.querySelectorAll(input)) : new Selection(input?.nodes ?? (input ? [input] : []));
  for (const method of ["find","text","html","children","contents","attr"]) select[method] = (...args) => new Selection([doc])[method](...args);
  Object.defineProperty(select, "length", {value: () => 1});
  return select;
}
globalThis.LoadDoc = loadDoc;

globalThis.fetch = async (url, options = {}) => {
  if (String(options.method ?? "GET").toUpperCase() !== "GET" || options.body) return unsupportedAPI();
  const allowed = new Set(["accept","accept-language","user-agent","referer","origin","content-type","cache-control","range"]);
  const headers = {};
  const entries = Object.entries(options.headers ?? {});
  if (entries.length > 16) return unsupportedAPI();
  for (const [name, raw] of entries) {
    const key = name.trim().toLowerCase(), value = String(raw);
    if (!allowed.has(key) || value.length > 2048 || /[\r\n]/.test(value)) return unsupportedAPI();
    headers[key] = value;
  }
  if (++networkCount > 24) { failedNetwork = true; throw new Error("Network request budget exceeded"); }
  const id = ++nextID;
  return new Promise((resolve, reject) => {
    pending.set(id, { resolve, reject });
    send({ kind: "fetch", id, url: String(url), headers });
  });
};

export async function runProvider(input) {
  preferences = input.preferences ?? {}; errorCount = 0; failedNetwork = false; unsupported = false;
  networkCount = 0; networkBytes = 0; httpFailures = 0;
  const compiled = ts.transpileModule(input.source, {
    reportDiagnostics: true,
    compilerOptions: { target: ts.ScriptTarget.ES2020, module: ts.ModuleKind.CommonJS, isolatedModules: true }
  });
  if (compiled.diagnostics?.some(d => d.category === ts.DiagnosticCategory.Error)) throw new Error("Invalid TypeScript");
  const module = {exports: {}};
  const Provider = new Function("module", "exports", compiled.outputText + "\n;return typeof Provider === 'function' ? Provider : (module.exports.default || module.exports.Provider);")(module, module.exports);
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
    const torrents = value.filter(row => row && typeof row.name === "string" && row.name.trim() && row.name.length <= 4096);
    if (value.length && !torrents.length) throw new Error("Invalid torrent entries");
    return { torrents, warnings: errorCount + httpFailures + value.length - torrents.length };
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
    const headers = Object.fromEntries(Object.entries(data.headers ?? {}).map(([key,value]) => [key.toLowerCase(), String(value)]));
    Object.defineProperty(headers,"get",{enumerable:false,value:key=>headers[String(key).toLowerCase()] ?? null});
    item.resolve({ ok: data.status >= 200 && data.status < 300, status: data.status, statusText: String(data.status), method: "GET",
      // Seanime returns body values synchronously; await also accepts these values.
      text: () => data.text, json: () => JSON.parse(data.text), url: data.url ?? "", headers,
      rawHeaders: Object.fromEntries(Object.entries(headers).map(([key,value]) => [key,[value]])), cookies: {}, redirected: false,
      contentType: headers["content-type"] ?? "", contentLength: new TextEncoder().encode(data.text ?? "").length });
    return;
  }
  if (data.kind !== "run") return;
  try { send({ kind: "result", result: await runProvider(data.input) }); }
  catch { send({ kind: "result", result: { error: "runtime" } }); }
};
