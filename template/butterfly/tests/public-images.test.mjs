import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { publicImages } from '../scripts/public-images.mjs';

test('exports referenced public images only, handles reference syntax, HTML and theme images', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'public-images-'));
  try {
    for (const name of ['article.png', 'about.png', 'background.svg', 'cover.png', 'reference.png', 'html.png', 'private-note.png'])
      fs.writeFileSync(path.join(dir, name), 'image');
    const content = {posts: [{body: '![image](/img/article.png)\n![ref][image]\n\n[image]: /img/reference.png\n\n<img src="/img/html.png">', cover: '/img/cover.png'}],
      about: '![](/img/about.png)', site: {}, theme: {backgroundImage: '/img/background.svg'}};
    const names = publicImages(content, dir).map(([name]) => name).sort();
    assert.deepEqual(names, ['about.png', 'article.png', 'background.svg', 'cover.png', 'html.png', 'reference.png']);
    fs.symlinkSync(path.join(dir, 'private-note.png'), path.join(dir, 'linked.png'));
    content.posts[0].body += '\n![](/img/linked.png)\n![](/img/../private-note.png)';
    assert.deepEqual(publicImages(content, dir).map(([name]) => name).sort(), names);
  } finally { fs.rmSync(dir, {recursive: true, force: true}); }
});
