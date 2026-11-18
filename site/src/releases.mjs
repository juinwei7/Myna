// 讀 GitHub Releases（docs/website.md §5）。還沒有任何發布、或連不上 GitHub 時回空陣列，網站改成教人從原始碼建置。
//
// 發布說明的格式（tag 的說明會變成 Release 的內文）：
//   九官鳥 2.1.0：一句話的副標
//   - 一行一條，用「- 」開頭，寫使用者看得到的改變

import { readFile } from 'node:fs/promises';

export const REPO = 'juinwei7/Myna';

function parse(release) {
  const lines = String(release.body ?? '').replace(/\r/g, '').split('\n');
  const first = lines.find((l) => l.trim()) ?? '';
  const subtitle = first.startsWith('- ') ? '' : (first.split(/[:：]/).slice(1).join('：').trim());
  const notes = [];
  for (const line of lines) {
    if (line.startsWith('- ')) notes.push(line.slice(2).trim());
    // 中文段之後空一行是英文段，網站只有中文，讀到這裡就停
    else if (notes.length && !line.trim()) break;
  }
  const dmg = (release.assets ?? []).find((a) => a.name.endsWith('.dmg'));
  return {
    version: release.tag_name.replace(/^v/, ''),
    tag: release.tag_name,
    date: (release.published_at ?? '').slice(0, 10),
    url: release.html_url,
    subtitle,
    notes,
    dmg: dmg ? { url: dmg.browser_download_url, size: dmg.size } : null,
  };
}

export async function loadReleases({ file } = {}) {
  let raw;
  if (file) {
    raw = JSON.parse(await readFile(file, 'utf8'));
  } else {
    try {
      const headers = { Accept: 'application/vnd.github+json', 'User-Agent': 'myna-site' };
      if (process.env.GITHUB_TOKEN) headers.Authorization = `Bearer ${process.env.GITHUB_TOKEN}`;
      const res = await fetch(`https://api.github.com/repos/${REPO}/releases?per_page=100`, { headers });
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      raw = await res.json();
    } catch (error) {
      console.warn(`讀不到 GitHub Releases（${error.message}），網站會顯示「從原始碼建置」`);
      return [];
    }
  }
  return raw.filter((r) => !r.draft && !r.prerelease).map(parse);
}
