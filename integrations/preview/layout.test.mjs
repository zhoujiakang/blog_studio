import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { resolveBlog } from './layout.mjs';
import { manifestIdentity, packageManifestIdentity } from './probe.mjs';

test('preview rejects old blogs and package-only roots without migration', async () => {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), 'inkjian-layout-'));
  try {
    await fs.mkdir(path.join(root, 'source/_posts'), { recursive: true });
    await fs.writeFile(path.join(root, 'source/_posts/a.md'), 'original');
    await fs.writeFile(path.join(root, 'package.json'), '{}');
    await assert.rejects(resolveBlog(root));
    await assert.rejects(manifestIdentity(root));
    assert.equal((await packageManifestIdentity(root)).lockHash, null);
    const marker = '{"formatVersion":1,"activeTemplate":"butterfly"}';
    await fs.writeFile(path.join(root, 'blog.json'), marker);
    await assert.rejects(resolveBlog(root), /格式/);
    assert.equal(await fs.readFile(path.join(root, 'blog.json'), 'utf8'), marker);
    assert.equal(await fs.readFile(path.join(root, 'source/_posts/a.md'), 'utf8'), 'original');
    assert.equal(await fs.access(path.join(root, 'resource')).then(() => true, () => false), false);
    await fs.mkdir(path.join(root, 'resource'));
    await fs.mkdir(path.join(root, 'template/butterfly'), { recursive: true });
    await fs.writeFile(path.join(root, 'blog.json'), '{"formatVersion":2,"activeTemplate":"butterfly"}');
    assert.equal((await resolveBlog(root)).packageRoot, path.join(await fs.realpath(root), 'template/butterfly/'));
    for (const activeTemplate of [null, 123, '../escape']) {
      await fs.writeFile(path.join(root, 'blog.json'), JSON.stringify({formatVersion: 2, activeTemplate}));
      await assert.rejects(resolveBlog(root), /格式/);
    }
  } finally { await fs.rm(root, {recursive: true, force: true}); }
});
