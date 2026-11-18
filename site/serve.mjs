// 本機預覽 site/dist：node site/serve.mjs，開 http://localhost:4322/。找不到時回 404 頁，會照 _redirects 轉址。

import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.join(path.dirname(fileURLToPath(import.meta.url)), 'dist');
const port = Number(process.env.PORT || 4322);
const TYPES = { '.html': 'text/html; charset=utf-8', '.css': 'text/css', '.png': 'image/png', '.avif': 'image/avif', '.ico': 'image/x-icon',
  '.txt': 'text/plain; charset=utf-8', '.xml': 'application/xml' };

const redirects = await readFile(path.join(root, '_redirects'), 'utf8')
  .then((text) => Object.fromEntries(text.trim().split('\n').map((line) => line.split(/\s+/).slice(0, 2))))
  .catch(() => ({}));

createServer(async (req, res) => {
  const url = new URL(req.url, 'http://localhost');
  if (redirects[url.pathname]) {
    res.writeHead(302, { Location: redirects[url.pathname] }).end();
    return;
  }
  let file = path.normalize(path.join(root, decodeURIComponent(url.pathname)));
  if (!file.startsWith(root)) file = path.join(root, '404.html');
  if (url.pathname.endsWith('/')) file = path.join(file, 'index.html');
  try {
    const body = await readFile(file);
    res.writeHead(200, { 'Content-Type': TYPES[path.extname(file)] ?? 'application/octet-stream' }).end(body);
  } catch {
    res.writeHead(404, { 'Content-Type': TYPES['.html'] }).end(await readFile(path.join(root, '404.html')));
  }
}).listen(port, '127.0.0.1', () => console.log(`http://localhost:${port}/`));
