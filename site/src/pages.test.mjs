// 官網頁面的檢查：node --test site/src/pages.test.mjs
// 不連網路、不讀檔，只看產生出來的 HTML。

import assert from 'node:assert/strict';
import { test } from 'node:test';
import { SAMPLES, MODELS } from './content.mjs';
import { atLeast, released, homePage, SHOT_SIZE } from './pages.mjs';

for (const name of ['studio', 'voices', 'versions', 'models']) SHOT_SIZE[name] = { width: 1920, height: 1168 };

const release = (version) => ({ version, tag: `v${version}`, date: '2026-11-18', url: '#', subtitle: '', notes: [], dmg: { url: '#', size: 1 } });
const home = (releases) => homePage({ site: 'https://example.test', css: '', releases });

test('版本比大小是比數字，不是比字串', () => {
  assert.ok(atLeast('2.1.0', '2.1.0'));
  assert.ok(atLeast('2.10.0', '2.9.0'));
  assert.ok(atLeast('3.0', '2.9.9'));
  assert.ok(!atLeast('2.0.9', '2.1.0'));
  assert.ok(!atLeast(undefined, '2.1.0'));
});

test('標了 since 的段落，最新版到了才放', () => {
  const items = ['一直都在', { since: '2.1.0', text: '新功能' }];
  assert.deepEqual(released(items, '2.0.0'), ['一直都在']);
  assert.deepEqual(released(items, '2.1.0'), ['一直都在', '新功能']);
  assert.deepEqual(released(items, undefined), ['一直都在']);
});

test('首頁不提還沒發布的功能', () => {
  const before = home([release('2.0.0')]);
  const after = home([release('2.1.0'), release('2.0.0')]);
  for (const phrase of ['第一段做好就開始播', '做完跟我說一聲']) {
    assert.ok(!before.includes(phrase), `2.0.0 的首頁不該出現「${phrase}」`);
    assert.ok(after.includes(phrase), `2.1.0 的首頁要有「${phrase}」`);
  }
  assert.ok(!home([]).includes('第一段做好就開始播'));
});

test('試聽：每個模型一段，按了才載入，網站仍然沒有外部的 script', () => {
  const html = home([release('2.0.0')]);
  const players = html.match(/<audio [^>]*>/g) ?? [];
  assert.equal(players.length, 8);
  assert.ok(players.every((tag) => tag.includes('controls') && tag.includes('preload="none"')));
  assert.deepEqual(SAMPLES.map((s) => s.name), MODELS.map((m) => m.name), '順序跟模型的表一樣');
  for (const sample of SAMPLES) assert.ok(html.includes(`src="/audio/${sample.id}.m4a"`));
  assert.ok(!/<script[^>]+src=/.test(html));
});
