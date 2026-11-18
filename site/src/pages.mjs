// 首頁、版本說明、404 的 HTML（docs/website.md §3）。整個網站沒有 JavaScript，深色模式跟著系統。

import { content as c, MODELS, GITHUB } from './content.mjs';

export function escape(text) {
  return String(text).replace(/[&<>"']/g, (ch) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[ch]);
}

const paragraphs = (ps) => ps.map((p) => `<p>${escape(p)}</p>`).join('\n');
const list = (items) => `<ul>${items.map((i) => `<li>${escape(i)}</li>`).join('')}</ul>`;

// 共用的外框：head、頁首、頁尾。path 是這一頁的網址（404 頁沒有，不放 canonical）
function layout({ site, css, path, title, description, body, head = '', hasChangelog }) {
  const canonical = path ? `<link rel="canonical" href="${site}${path}">` : '<meta name="robots" content="noindex">';
  const home = path === '/' ? '' : '/';
  return `<!doctype html>
<html lang="zh-Hant-TW">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${escape(title)}</title>
<meta name="description" content="${escape(description)}">
${canonical}
<meta property="og:type" content="website">
<meta property="og:site_name" content="${escape(c.fullName)}">
<meta property="og:title" content="${escape(title)}">
<meta property="og:description" content="${escape(description)}">
<meta property="og:image" content="${site}/og.png">
${path ? `<meta property="og:url" content="${site}${path}">` : ''}
<meta name="twitter:card" content="summary_large_image">
<link rel="icon" href="/favicon.png" type="image/png">
<link rel="apple-touch-icon" href="/apple-touch-icon.png">
<style>${css}</style>
${head}
</head>
<body>
<header class="top">
  <a class="home" href="/"><img src="/icon.png" alt="" width="26" height="26">${escape(c.name)}</a>
  <nav>
    <a class="wide-only" href="${home}#features">${c.nav.features}</a>
    <a class="wide-only" href="${home}#models">${c.nav.models}</a>
    <a class="wide-only" href="${home}#privacy">${c.nav.privacy}</a>
    <a href="${home}#download">${c.nav.download}</a>
    ${hasChangelog ? `<a href="/changelog/">${c.nav.changelog}</a>` : ''}
    <a href="${GITHUB}">${c.nav.github}</a>
  </nav>
</header>
<main>
${body}
</main>
<footer>
  <span>${escape(c.footer)}</span>
  <a href="${GITHUB}">GitHub</a>
  ${hasChangelog ? `<a href="/changelog/">${c.nav.changelog}</a>` : ''}
  <a href="${GITHUB}/blob/main/LICENSE">MIT 授權</a>
</footer>
</body>
</html>
`;
}

// 截圖：優先用 AVIF（960、1920 兩種寬度），PNG 當備援。first 是第一屏那張，不延後載入
function shot(name, { first = false } = {}) {
  const size = SHOT_SIZE[name];
  return `<figure class="wide">
  <picture>
    <source type="image/avif" srcset="/images/${name}-960.avif 960w, /images/${name}.avif 1920w" sizes="(max-width: 1000px) 100vw, 960px">
    <img class="shot" src="/images/${name}.png" alt="${escape(c.shots[name])}" width="${size.width}" height="${size.height}"${first ? ' fetchpriority="high"' : ' loading="lazy" decoding="async"'}>
  </picture>
</figure>`;
}

// 截圖的尺寸在建置時讀進來（build.mjs），寫進 width、height，載入時版面才不會跳
export const SHOT_SIZE = {};

function modelsTable() {
  const head = c.models.columns.map((h) => `<th>${h}</th>`).join('');
  const rows = MODELS.map((m) => `<tr><td>${escape(m.name)}</td><td>${escape(m.modes)}</td><td class="num">${m.size}</td><td>${escape(m.license)}</td><td class="num">${m.cer}</td><td>${escape(m.note)}</td></tr>`);
  return `<div class="scroll"><table class="models"><thead><tr>${head}</tr></thead><tbody>${rows.join('')}</tbody></table></div>`;
}

function downloadSection(latest) {
  const d = c.download;
  const req = d.requirements.map(([k, v]) => `<div><dt>${k}</dt><dd>${escape(v)}</dd></div>`).join('');
  const source = `<h3>${d.sourceTitle}</h3>
    <p>${escape(d.sourceText)}</p>
    <pre><code>${escape(d.sourceCommands)}</code></pre>`;
  // 還沒有發布安裝檔時，只教人從原始碼建置
  const install = latest?.dmg
    ? `<p class="get"><a class="download" href="${latest.dmg.url}">${escape(d.button(latest.version))}</a></p>
    <h3>${d.firstTitle}</h3>
    <p>${escape(d.firstText)}</p>
    <ol class="steps">${d.steps.map((s) => `<li>${escape(s)}</li>`).join('')}</ol>
    ${source}`
    : `<p>${escape(d.none)}</p>
    <pre><code>${escape(d.sourceCommands)}</code></pre>`;
  return `<section class="part col" id="download">
    <h2>${d.heading}</h2>
    <dl class="req">${req}</dl>
    ${install}
  </section>`;
}

function schema(site, latest) {
  const data = {
    '@context': 'https://schema.org',
    '@type': 'SoftwareApplication',
    name: c.fullName,
    applicationCategory: 'MultimediaApplication',
    operatingSystem: 'macOS 14+',
    description: c.description,
    url: `${site}/`,
    image: `${site}/icon.png`,
    offers: { '@type': 'Offer', price: '0', priceCurrency: 'USD' },
    license: 'https://opensource.org/licenses/MIT',
    ...(latest ? { softwareVersion: latest.version, datePublished: latest.date } : {}),
  };
  // JSON 放在 script 標籤裡，「<」要跳脫，不然內文裡的 </script> 會把標籤提前結束
  return `<script type="application/ld+json">${JSON.stringify(data).replace(/</g, '\\u003c')}</script>`;
}

export function homePage({ site, css, releases }) {
  const latest = releases[0] ?? null;
  const body = `<section class="intro">
  <img src="/icon.png" alt="" width="96" height="96">
  <h1>${escape(c.intro.heading)}</h1>
  <p>${escape(c.intro.text)}</p>
  <div class="actions">
    <a class="download" href="#download">${escape(c.intro.download(latest?.dmg ? latest.version : null))}</a>
    <a class="second" href="${GITHUB}">${escape(c.intro.source)}</a>
  </div>
  <small>${escape(c.intro.small)}</small>
</section>
${shot('studio', { first: true })}

<section class="part col" id="features">
  <h2>${escape(c.features.heading)}</h2>
  ${paragraphs(c.features.paragraphs)}
</section>

<section class="part">
  <div class="col">
    <h2>${escape(c.voices.heading)}</h2>
    ${paragraphs(c.voices.paragraphs)}
    <p class="note">${escape(c.voices.note)}</p>
  </div>
  ${shot('voices')}
</section>

<section class="part">
  <div class="col">
    <h2>${escape(c.compare.heading)}</h2>
    ${paragraphs(c.compare.paragraphs)}
  </div>
  ${shot('versions')}
</section>

<section class="part" id="models">
  <div class="col">
    <h2>${escape(c.models.heading)}</h2>
    ${paragraphs(c.models.paragraphs)}
  </div>
  ${shot('models')}
  <div class="wide">
    ${modelsTable()}
    <p class="note" style="margin-top:12px">${escape(c.models.note)}</p>
  </div>
</section>

<section class="part col" id="privacy">
  <h2>${escape(c.privacy.heading)}</h2>
  <p>${escape(c.privacy.text)}</p>
  <div class="two">
    <div><h3>${c.privacy.stays.title}</h3>${list(c.privacy.stays.items)}</div>
    <div><h3>${c.privacy.leaves.title}</h3>${list(c.privacy.leaves.items)}</div>
  </div>
  <p class="note">${escape(c.privacy.note)}</p>
</section>

<section class="part col" id="mcp">
  <h2>${escape(c.mcp.heading)}</h2>
  ${paragraphs(c.mcp.paragraphs)}
  <pre><code>${escape(c.mcp.command)}</code></pre>
  <p>${escape(c.mcp.after)}</p>
</section>

${downloadSection(latest)}

<section class="part col" id="faq">
  <h2>${escape(c.faq.heading)}</h2>
  <div class="faq">
    ${c.faq.items.map(([q, a]) => `<details><summary>${escape(q)}</summary><p>${escape(a)}</p></details>`).join('\n    ')}
  </div>
</section>`;
  return layout({ site, css, path: '/', title: c.title, description: c.description, body, head: schema(site, latest), hasChangelog: releases.length > 0 });
}

export function changelogPage({ site, css, releases }) {
  const g = c.changelog;
  const items = releases.map((r, i) => `<article class="release" id="v${r.version}">
    <h2>${escape(c.name)} ${r.version}</h2>
    <p class="meta">${r.date}${i === 0 ? `　${g.latest}` : ''}${i === 0 && r.dmg ? `<a href="${r.dmg.url}">${g.download}</a>` : ''}<a href="${r.url}">${g.onGitHub}</a></p>
    ${r.subtitle ? `<p>${escape(r.subtitle)}</p>` : ''}
    ${r.notes.length ? list(r.notes) : ''}
  </article>`);
  const body = `<section class="col" style="padding-top:40px">
  <h1 style="font-size:32px">${g.title}</h1>
  ${items.join('\n')}
</section>`;
  return layout({ site, css, path: '/changelog/', title: `${g.title}｜${c.fullName}`, description: g.description, body, hasChangelog: true });
}

export function notFoundPage({ site, css, releases }) {
  const n = c.notFound;
  const body = `<section class="intro">
  <h1>${n.title}</h1>
  <p>${n.text}</p>
  <div class="actions"><a class="second" href="/">${n.home}</a></div>
</section>`;
  return layout({ site, css, title: `${n.title}｜${c.fullName}`, description: n.text, body, hasChangelog: releases.length > 0 });
}

// 給 AI 搜尋引擎看的純文字摘要
export function llmsTxt({ site, releases }) {
  const latest = releases[0];
  return `# ${c.fullName}

> ${c.description}

- 網站：${site}/
- 原始碼：${GITHUB}
- 授權：MIT（程式碼）；語音模型各有自己的授權
- 系統需求：macOS 14 以上、Apple Silicon
${latest ? `- 最新版：${latest.version}（${latest.date}）\n` : ''}
## 模型

${MODELS.map((m) => `- ${m.name}：${m.modes}，${m.size}，授權 ${m.license}，中文測試錯字率 ${m.cer}`).join('\n')}

## 常見問題

${c.faq.items.map(([q, a]) => `### ${q}\n${a}`).join('\n\n')}
`;
}
