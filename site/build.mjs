// 產生九官鳥官網到 site/dist/（docs/website.md §5）。只用 Node 內建功能，不用裝套件。
//
//   node site/build.mjs                    讀 GitHub Releases，產生網站
//   node site/build.mjs --releases <檔案>   改讀這份 JSON（跟 API 同樣格式），不連網路
//
// 環境變數：SITE_URL（預設 https://myna.weibuilds.com）、GITHUB_TOKEN（選填，避免 API 次數限制）

import { cp, mkdir, readFile, rm, stat, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { parseArgs } from 'node:util';
import { loadReleases } from './src/releases.mjs';
import { homePage, changelogPage, notFoundPage, llmsTxt, SHOT_SIZE } from './src/pages.mjs';

const here = path.dirname(fileURLToPath(import.meta.url));
const repo = path.resolve(here, '..');
const { values: args } = parseArgs({ options: { releases: { type: 'string' }, out: { type: 'string' } } });
const out = path.resolve(args.out ?? path.join(here, 'dist'));
const site = (process.env.SITE_URL || 'https://myna.weibuilds.com').replace(/\/+$/, '');
const SHOTS = ['studio', 'voices', 'versions', 'models'];

// PNG 的寬高在檔頭第 16～24 個位元組
async function pngSize(file) {
  const head = (await readFile(file)).subarray(16, 24);
  return { width: head.readUInt32BE(0), height: head.readUInt32BE(4) };
}

async function write(route, text) {
  const file = path.join(out, route);
  await mkdir(path.dirname(file), { recursive: true });
  await writeFile(file, text);
}

try {
  const releases = await loadReleases({ file: args.releases });
  for (const name of SHOTS) {
    SHOT_SIZE[name] = await pngSize(path.join(repo, `docs/images/${name}.png`));
    // 缺 AVIF 就停下來，提醒先跑 make-images.sh（截圖換過要重跑）
    for (const suffix of ['', '-960']) {
      await stat(path.join(here, `public/images/${name}${suffix}.avif`)).catch(() => {
        throw new Error(`缺 site/public/images/${name}${suffix}.avif，先跑 site/make-images.sh`);
      });
    }
  }
  const css = await readFile(path.join(here, 'src/style.css'), 'utf8');

  await rm(out, { recursive: true, force: true });
  await cp(path.join(here, 'public'), out, { recursive: true });
  // 截圖的 PNG 只有一份，在 docs/images（README 也用這份），當 AVIF 的備援
  for (const name of SHOTS) await cp(path.join(repo, `docs/images/${name}.png`), path.join(out, `images/${name}.png`));
  await cp(path.join(repo, 'docs/images/icon.png'), path.join(out, 'icon.png'));

  const page = { site, css, releases };
  await write('index.html', homePage(page));
  await write('404.html', notFoundPage(page));
  const routes = ['/'];
  if (releases.length) {
    await write('changelog/index.html', changelogPage(page));
    routes.push('/changelog/');
    // /download 永遠轉到最新版的 DMG，給 README、社群貼文用
    if (releases[0].dmg) await write('_redirects', `/download ${releases[0].dmg.url} 302\n`);
  }
  await write('robots.txt', `User-agent: *\nAllow: /\n\nSitemap: ${site}/sitemap.xml\n`);
  await write('sitemap.xml', `<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n${routes.map((r) => `  <url><loc>${site}${r}</loc></url>`).join('\n')}\n</urlset>\n`);
  await write('llms.txt', llmsTxt(page));
  console.log(`已產生 ${path.relative(repo, out)}/：${routes.length} 頁，${releases.length ? `最新版 ${releases[0].version}` : '還沒有發布版本'}`);
} catch (error) {
  console.error(`建置失敗：${error.message}`);
  process.exit(1);
}
