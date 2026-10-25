import {readFile, stat} from 'node:fs/promises';
import assert from 'node:assert/strict';
import {fileURLToPath} from 'node:url';
import path from 'node:path';

const root = fileURLToPath(new URL('./dist/', import.meta.url));
const spec = await readFile(new URL('../pubspec.yaml', import.meta.url), 'utf8');
const version = spec.match(/^version: (\d+\.\d+\.\d+)/m)[1];
const releases = JSON.parse(await readFile(path.join(root, 'releases.json'), 'utf8'));
const downloadPaths = new Set(releases.map(item => item.path));
const latest = JSON.parse(await readFile(path.join(root, 'release.json'), 'utf8'));
assert.equal(latest.name, `PvZ-Formation-Editor-${version}-windows-x64.zip`);
const pages = ['index.html', 'docs/index.html', 'en/index.html', 'en/docs/index.html',
  `releases/${version}/index.html`, `en/releases/${version}/index.html`];
let links = 0;
for (const page of pages) {
  const html = await readFile(path.join(root, page), 'utf8');
  assert.ok(html.includes(version), `${page}: version`);
  assert.match(html, /id="language-picker"/);
  for (const language of ['auto', 'zh', 'en']) assert.ok(html.includes(`value="${language}"`));
  assert.ok(html.includes('https://github.com/jadepeakpoet/pvz-formation-editor'));
  assert.ok(html.includes('https://qm.qq.com/q/BbkV57ELaa'));
  assert.ok(!/href="[^\"]*-source\.zip"/.test(html), 'Source downloads belong on GitHub');
  assert.ok(!html.includes('获取含僵尸布局'), 'Obsolete button name');
  assert.ok(!html.includes('游戏阵型：获取'), 'Obsolete section');
  for (const match of html.matchAll(/(?:href|src)="([^\"]+)"/g)) {
    const url = new URL(match[1], 'https://local.test/'+page);
    if (url.origin !== 'https://local.test') continue;
    links++;
    if (downloadPaths.has(url.pathname)) continue; // Served by the download Worker.
    let target = path.join(root, decodeURIComponent(url.pathname));
    if (url.pathname.endsWith('/')) target = path.join(target, 'index.html');
    await stat(target);
    if (url.hash && target.endsWith('.html')) {
      const body = await readFile(target, 'utf8');
      assert.ok(body.includes(`id="${url.hash.slice(1)}"`), `${page}: missing ${url.hash}`);
    }
  }
}
assert.equal(await readFile(path.join(root, 'license.txt'), 'utf8'),
  await readFile(new URL('../LICENSE', import.meta.url), 'utf8'));
console.log(`Pages passed: ${pages.length} pages, ${links} local links, version, language, downloads and license.`);
