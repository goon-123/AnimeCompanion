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

test('documented Seanime DOM traversal and callable length work on torrent tables', () => {
  const $ = loadDoc('<table><tbody><tr class="release" data-episode="7"><td class="name"><a href="/view/7">Episode 7</a></td><td class="size">1 GiB</td><td class="seed">42</td></tr><tr class="release"><td>Other</td></tr></tbody></table>');
  assert.equal($('tr').length(), 2);
  assert.ok($('tr').length > 0);
  assert.equal($('a').parent().next().text(), '1 GiB');
  assert.equal($('a').closest('tr').find('.seed').text(), '42');
  assert.equal($('tr').first().data('episode'), '7');
  assert.equal($('tr').first().next().prev().is('.release'), true);
  assert.equal($('tr').eq(-1).text(), 'Other');
  assert.equal($('tr').has('a').length(), 1);
  assert.equal($('tr').not((_, e) => e.find('a').length() > 0).text(), 'Other');
  assert.equal($('tr').first().find('a').end().length(), 1);
});

test('read-only public fetch headers and response metadata are supported', async () => {
  response = {status: 200, text:'[{"name":"Header fixture"}]', headers:{'content-type':'application/json'}, url:'https://provider.example/feed'};
  const value = await runProvider(input(`class Provider {async search(){const r=await fetch('https://provider.example/feed',{headers:{'Accept':'application/json','User-Agent':'Provider fixture'}}); if(r.headers['content-type']!=='application/json'||r.method!=='GET'||!r.contentLength)throw new Error('response ABI');return r.json();}}`));
  assert.equal(value.torrents[0].name, 'Header fixture');
  assert.equal(calls.at(-1).headers.accept, 'application/json');
  for (const options of ["{headers:{Cookie:'private'}}", "{headers:{Host:'other.example'}}", "{headers:{Accept:'x\\r\\ny: z'}}"]) {
    await assert.rejects(runProvider(input(`class Provider {async search(){await fetch('https://provider.example/feed',${options});return [];}}`)));
  }
  response = {status:200,text:'[]'};
});

test('named and default TypeScript Provider exports run in the isolated module', async () => {
  for (const prefix of ['export ', 'export default ']) {
    const result = await runProvider(input(`${prefix}class Provider {search(){return [{name:'Exported provider'}]}}`));
    assert.equal(result.torrents[0].name,'Exported provider');
  }
});

test('malformed entries do not discard valid torrents or masquerade as empty results', async () => {
  const mixed = await runProvider(input(`class Provider {search(){return [null,{name:'Valid release'},{foo:'broken'}]}}`));
  assert.equal(mixed.torrents.length,1); assert.equal(mixed.warnings,2);
  await assert.rejects(runProvider(input(`class Provider {search(){return [null,{foo:'broken'}]}}`)));
});

test('two bundled providers keep preferences, networking and errors isolated', async () => {
  const bundle = await readFile(new URL('../../App/SeanimeRuntimeResources/worker.js', import.meta.url),'utf8');
  async function run(label, fail) {
    const worker = new Worker(`const {parentPort}=require('node:worker_threads');globalThis.process=undefined;globalThis.self={postMessage:m=>parentPort.postMessage(m)};${bundle}\n;parentPort.on('message',data=>self.onmessage({data}));parentPort.postMessage({ready:true});`,{eval:true});
    try {
      await new Promise((resolve,reject)=>{worker.once('message',resolve);worker.once('error',reject)});
      const result = new Promise((resolve,reject)=>{
        const timer=setTimeout(()=>reject(new Error('provider fixture timeout')),10000);
        worker.on('message',message=>{
          if(message.kind==='fetch') worker.postMessage({kind:'response',id:message.id,status:200,text:'[{"name":"'+label+'"}]'});
          if(message.kind==='result'){clearTimeout(timer);resolve(message.result)}
        });
      });
      worker.postMessage({kind:'run',input:{...input(`class Provider {async search(){if($getUserPreference('label')!=='${label}')throw new Error('crossed preferences'); ${fail ? "throw new Error('owned provider failure');" : "const r=await fetch('https://provider.example/feed');return r.json();"}}}`),preferences:{label}}});
      return await result;
    } finally { await worker.terminate(); }
  }
  const [first,second]=await Promise.all([run('First',true),run('Second',false)]);
  assert.equal(first.error,'runtime'); assert.equal(second.torrents[0].name,'Second');
  const both=await Promise.all([run('One',false),run('Two',false)]);
  assert.deepEqual(both.map(result=>result.torrents[0].name),['One','Two']);
});
