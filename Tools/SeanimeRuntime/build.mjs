import { build } from 'esbuild';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
const root = dirname(fileURLToPath(import.meta.url));
const output = resolve(root, '../../App/SeanimeRuntimeResources');
await mkdir(output, { recursive: true });
const result = await build({ entryPoints: [resolve(root, 'worker.js')], outfile: resolve(output, 'worker.js'), metafile: true,
  bundle: true, platform: 'browser', format: 'iife', minify: true, target: ['safari17'],
  legalComments: 'eof', define: { 'process.env.NODE_ENV': '"production"' } });
const packages = new Map();
for (const input of Object.keys(result.metafile.inputs).filter(p => p.includes('node_modules/'))) {
  let folder = dirname(resolve(root, input));
  while (folder.includes('node_modules')) {
    try {
      const pkg = JSON.parse(await readFile(resolve(folder, 'package.json'), 'utf8'));
      if (!pkg.name || !pkg.version) { folder = dirname(folder); continue; }
      packages.set(`${pkg.name}@${pkg.version}`, {folder, pkg}); break;
    } catch { folder = dirname(folder); }
  }
}
let licenses = 'Bundled on-device Seanime compatibility runtime. Dependencies are not Seanime runtime code.\n';
for (const {folder, pkg} of [...packages.values()].sort((a,b) => a.pkg.name.localeCompare(b.pkg.name))) {
  const name = pkg.name;
  let found = '';
  for (const file of ['LICENSE', 'LICENSE.txt', 'LICENSE.md', 'LICENSE-MIT.txt']) {
    try { found = await readFile(resolve(folder, file), 'utf8'); break; } catch {}
  }
  if (!found) throw new Error('Missing license: ' + name);
  licenses += `\n===== ${name} ${pkg.version} (${pkg.license}) =====\n${found}\n`;
  if (name === 'typescript') licenses += '\n' + await readFile(resolve(folder, 'ThirdPartyNoticeText.txt'), 'utf8');
}
await writeFile(resolve(output, 'THIRD_PARTY_NOTICES.txt'), licenses);
