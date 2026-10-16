import test from 'node:test';
import assert from 'node:assert/strict';
import { Worker } from 'node:worker_threads';
import { readFile } from 'node:fs/promises';

const originalConsole = globalThis.console;
const calls = [];
let response = { status: 200, text: '[]' }, networkError = false;
globalThis.self = { postMessage(message) {
  if (message.kind !== 'fetch') return;
  calls.push(message);
  queueMicrotask(() => self.onmessage({ data: {kind: 'response', id: message.id, ...response, error: networkError} }));
}};
const { runProvider, loadDoc, parseFilename } = await import('./worker.js');
globalThis.console = originalConsole;
const input = source => ({ source, method: 'search', preferences: {}, allowAdult: false, options: {query: 'Fixture', media: {id: 1, synonyms: []}} });

test('real TypeScript syntax is compiled, not regex-stripped', async () => {
  const result = await runProvider(input(`interface Item { name: string }; class Provider {
    private label: string = 'Typed'; getSettings() { return {supportsAdult:false} }
    async search(opts: {query:string}): Promise<Item[]> { return [{name:this.label + opts.query}]; }
  }`));
  assert.equal(result.torrents[0].name, 'TypedFixture');
});
test('Seanime sync response bodies and awaited bodies both work', async () => {
  response = {status: 200, text: '[{"name":"EN","infoHash":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}]'};
  for (const expression of ['r.json()', 'await r.json()', 'JSON.parse(r.text())', 'JSON.parse(await r.text())']) {
    const result = await runProvider(input(`class Provider { async search() { const r=await fetch('https://provider.example/feed'); return ${expression}; } }`));
    assert.equal(result.torrents[0].name, 'EN');
  }
  assert.equal(calls.length, 4);
});
test('preferences only contain values explicitly supplied for this extension', async () => {
  const value = input(`class Provider { search() { return [{name:$getUserPreference('feed') + ':' + $getUserPreference('torBoxKey')}]; } }`);
  value.preferences = {feed: 'chosen'};
  assert.equal((await runProvider(value)).torrents[0].name, 'chosen:');
});
test('LoadDoc uses inert DOM selections and Seanime element wrappers', () => {
  const $ = loadDoc('<a class="card-footer-item" href="magnet:?xt=urn:btih:aaa">A</a><section><p>A</p><p>B</p></section>');
  let href;
  $('a[href^="magnet:"]').each((_, el) => { href = $(el).attr('href'); return false; });
  assert.equal(href, 'magnet:?xt=urn:btih:aaa');
  assert.deepEqual($('section').children('p').filter((i,e) => e.text() !== 'A').map((i,e) => e.text()), ['B']);
});
test('filename hints do not fabricate unnamed audio languages', () => {
  const parsed = parseFilename('[Group] Anime - 09 [1080p].mkv');
  assert.deepEqual(parsed.episode_number, ['09']); assert.equal(parsed.video_resolution, '1080p');
  assert.deepEqual(parsed.language, []); assert.equal(parsed.release_group, 'Group');
  assert.deepEqual(parseFilename('Anime S02E07 EN.mkv').episode_number, ['07']);
});
test('unknown filename episode remains unknown', () => {
  assert.deepEqual(parseFilename('Anime [1080p HEVC].mkv').episode_number, []);
});
test('known adult provider is blocked before search or network', async () => {
  const count = calls.length;
  const value = await runProvider(input(`class Provider { getSettings() {return {supportsAdult:true}}; async search() {await fetch('https://provider.example/feed');return [];} }`));
  assert.equal(value.error, 'adult'); assert.equal(calls.length, count);
});
test('adult opt-in permits that provider', async () => {
  const value = input(`class Provider {getSettings(){return {supportsAdult:true}};search(){return [{name:'Allowed fixture'}]}}`);
  value.allowAdult = true;
  assert.equal((await runProvider(value)).torrents.length, 1);
});
test('network errors cannot become successful empty responses even if caught', async () => {
  networkError = true;
  await assert.rejects(runProvider(input(`class Provider {async search(){try {await fetch('https://provider.example/feed');}catch{} return [];}}`)));
  networkError = false;
  response = {status: 403, text: '[]'};
  await assert.rejects(runProvider(input(`class Provider {async search(){const r=await fetch('https://provider.example/feed');return r.json();}}`)));
  response = {status: 200, text: '[]'};
});
test('unimplemented APIs cannot silently masquerade as no results', async () => {
  await assert.rejects(runProvider(input(`class Provider {search(){try {$scannerUtils.buildSmartSearchTitles([]);}catch{} return [];}}`)));
});
test('writes and custom-header fetches are rejected', async () => {
  for (const options of [`{method:'POST',body:'data'}`, `{headers:{Authorization:'x'}}`]) {
    await assert.rejects(runProvider(input(`class Provider {async search(){return await fetch('https://provider.example/feed',${options});}}`)));
  }
});
test('network request count is bounded even when provider catches errors', async () => {
  await assert.rejects(runProvider(input(`class Provider {async search(){for(let i=0;i<25;i++){try{await fetch('https://provider.example/feed');}catch{}}return [];}}`)));
});
test('malformed and oversized result lists fail', async () => {
  for (const source of [`class Provider {search(){return {};}}`, `class Provider {search(){return Array.from({length:1001},()=>({name:'Too many'}));}}`, 'class Wrong {}']) {
    await assert.rejects(runProvider(input(source)));
  }
});
test('bundled worker can be terminated while extension JavaScript spins', async () => {
  const bundle = await readFile(new URL('../../App/SeanimeRuntimeResources/worker.js', import.meta.url), 'utf8');
  const worker = new Worker(`const {parentPort}=require('node:worker_threads');globalThis.process=undefined;globalThis.self={postMessage:m=>parentPort.postMessage(m)};${bundle}\n;parentPort.on('message',data=>self.onmessage({data}));parentPort.postMessage({ready:true});`, {eval: true});
  try {
    await new Promise((resolve,reject) => { worker.once('message',resolve); worker.once('error',error=>reject(new Error(error.message))); });
    worker.postMessage({kind:'run',input:input('class Provider {search(){while(true){}}}')});
    await new Promise(resolve => setTimeout(resolve, 150));
    const code = await worker.terminate(); assert.equal(typeof code, 'number');
  } finally { await worker.terminate(); }
});
