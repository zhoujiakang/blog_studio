import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { loadContent, parsePost } from '../scripts/content.mjs';

test('current article attributes, extension fields, date and Markdown remain usable', () => {
  const p = parsePost(
    '---\ntitle: 中文标题\ndate: 2026-10-08 10:00:00\ntags: [Vue, 博客]\ncategories: [技术/前端, 随笔]\ncustom:\n  enabled: true\n  count: 2\n  value: "001"\n---\n\n## Heading\n\n```yaml\ntitle: Code example\n```\n',
    'sub/中文.md'
  );
  assert.equal(p.id, 'sub/中文');
  assert.equal(p.date, '2026-10-08T02:00:00.000Z');
  assert.deepEqual(p.tags, ['Vue', '博客']);
  assert.deepEqual(p.categories, ['技术/前端', '随笔']);
  assert.deepEqual(p.meta.custom, { enabled: true, count: 2, value: '001' });
  assert.match(p.body, /```yaml\ntitle: Code example/);
});
test('published false and draft true never enter public content', () => {
  for (const flag of ['published: false', 'draft: true'])
    assert.equal(
      parsePost(`---\ntitle: hidden\n${flag}\n---\nsecret`, 'hidden.md'),
      null
    );
});
test('bad YAML, invalid date and incomplete header fail visibly', () => {
  for (const source of [
    '---\ntitle: [broken\n---\nbody',
    '---\ntitle: hi',
    '---\ndate: invalid\n---\nbody',
    '---\n- list\n---\nbody',
  ])
    assert.throws(() => parsePost(source, 'invalid.md'));
});
test('plain Markdown and slug have stable routes', () => {
  assert.equal(parsePost('# Text without header', 'plain.md').title, 'plain');
  assert.equal(parsePost('---\nslug: my-post\ntags: [Vue]\n---\nbody', 'x.md').id, 'my-post');
});
test('project reads resource posts only, preserves input and excludes private drafts', () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'vue-blog-'));
  try {
    seed(root);
    fs.mkdirSync(path.join(root, 'resource/posts'), { recursive: true });
    fs.mkdirSync(path.join(root, 'resource/drafts'), { recursive: true });
    const raw = '---\ntitle: Visible\ndate: 2026-10-01\n---\n\nVisible body\n';
    fs.writeFileSync(path.join(root, 'resource/posts/a.md'), raw);
    fs.writeFileSync(
      path.join(root, 'resource/posts/b.md'),
      '---\ntitle: Hidden\npublished: false\n---\nPRIVATE_POST'
    );
    fs.writeFileSync(path.join(root, 'resource/drafts/private.md'), 'PRIVATE_DRAFT');
    fs.mkdirSync(path.join(root, 'resource/notes'), { recursive: true });
    fs.writeFileSync(path.join(root, 'resource/notes/note.md'), 'PRIVATE_NOTE');
    fs.writeFileSync(path.join(root, 'resource/posts/file.tmp'), 'TEMPORARY');
    const loaded = loadContent(root);
    assert.equal(loaded.posts.length, 1);
    assert.equal(loaded.posts[0].title, 'Visible');
    assert.ok(!JSON.stringify(loaded).includes('PRIVATE'));
    assert.equal(fs.readFileSync(path.join(root, 'resource/posts/a.md'), 'utf8'), raw);
  } finally {
    fs.rmSync(root, { recursive: true, force: true });
  }
});
test('duplicate slugs stop a build instead of silently replacing an article', () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'vue-blog-'));
  try {
    seed(root);
    fs.mkdirSync(path.join(root, 'resource/posts'), { recursive: true });
    for (const id of ['a', 'b'])
      fs.writeFileSync(
        path.join(root, `resource/posts/${id}.md`),
        '---\nslug: same\n---\nbody'
      );
    assert.throws(() => loadContent(root), /重复/);
  } finally {
    fs.rmSync(root, { recursive: true, force: true });
  }
});
test('shared resources, About and template config work without legacy config and exclude notes', () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'vue-shared-'));
  try {
    for (const dir of [
      'resource/posts',
      'resource/drafts',
      'resource/notes',
      'template/butterfly',
    ])
      fs.mkdirSync(path.join(root, dir), { recursive: true });
    fs.writeFileSync(
      path.join(root, 'blog.json'),
      JSON.stringify({ formatVersion: 2, activeTemplate: 'butterfly' })
    );
    const template = JSON.parse(
      fs.readFileSync(new URL('../template.json', import.meta.url), 'utf8')
    );
    for (const field of template.fields) {
      if (field.key === 'themeColor') field.value = '#123ABC';
      if (field.key === 'announcement') field.value = '当前模版公告';
      if (field.key === 'backgroundImage') field.value = '/img/custom.png';
    }
    fs.writeFileSync(
      path.join(root, 'template/butterfly/template.json'),
      JSON.stringify(template)
    );
    fs.writeFileSync(
      path.join(root, 'resource/posts/a.md'),
      '---\ntitle: Shared Article\n---\nSHARED_BODY'
    );
    fs.writeFileSync(path.join(root, 'resource/drafts/draft.md'), 'PRIVATE_DRAFT');
    fs.writeFileSync(path.join(root, 'resource/notes/note.md'), 'PRIVATE_NOTE');
    fs.writeFileSync(path.join(root, 'resource/about.md'), '# 公共关于\n\nABOUT_BODY');
    const loaded = loadContent(path.join(root, 'template/butterfly'));
    assert.equal(loaded.posts.length, 1);
    assert.equal(loaded.posts[0].title, 'Shared Article');
    assert.equal(loaded.theme.themeColor, '#123ABC');
    assert.equal(loaded.theme.backgroundImage, '/img/custom.png');
    assert.equal(loaded.theme.announcement, '当前模版公告');
    assert.match(loaded.about, /ABOUT_BODY/);
    assert.doesNotMatch(JSON.stringify(loaded), /PRIVATE_NOTE|PRIVATE_DRAFT/);
  } finally {
    fs.rmSync(root, { recursive: true, force: true });
  }
});

function seed(root) {
  fs.mkdirSync(path.join(root, 'template/butterfly'), { recursive: true });
  fs.copyFileSync(new URL('../template.json', import.meta.url), path.join(root, 'template/butterfly/template.json'));
  fs.writeFileSync(path.join(root, 'blog.json'), JSON.stringify({formatVersion: 2, activeTemplate: 'butterfly'}));
}

test('old directories and version 1 are rejected without changing files', () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'vue-old-'));
  try {
    fs.mkdirSync(path.join(root, 'source/_posts'), {recursive: true});
    fs.writeFileSync(path.join(root, 'source/_posts/a.md'), 'OLD_BODY');
    assert.throws(() => loadContent(root), /blog.json/);
    fs.writeFileSync(path.join(root, 'blog.json'), JSON.stringify({formatVersion: 1, activeTemplate: 'butterfly'}));
    assert.throws(() => loadContent(root), /格式/);
    assert.equal(fs.readFileSync(path.join(root, 'source/_posts/a.md'), 'utf8'), 'OLD_BODY');
    assert.equal(fs.existsSync(path.join(root, 'resource')), false);
  } finally { fs.rmSync(root, { recursive: true, force: true }); }
});

test('summary only uses explicit metadata, never article body', () => {
  assert.equal(parsePost('# Heading\nOpening text', 'plain.md').summary, '');
  assert.equal(parsePost('---\ndescription: ""\n---\nBody text', 'empty.md').summary, '');
  assert.equal(parsePost('---\ndescription: Summary\nexcerpt: Other\n---\nBody', 'explicit.md').summary, 'Summary');
  assert.equal(parsePost('---\nexcerpt: Excerpt\n---\nBody', 'excerpt.md').summary, '');
  assert.equal(parsePost('---\nabbrlink: 42\n---\nBody', 'filename.md').id, 'filename');
});

 test('invalid current attribute types fail rather than being coerced', () => {
  for (const field of ['draft: "true"', 'published: "false"', 'tags: Vue', 'categories: [[技术, 前端]]'])
    assert.throws(() => parsePost(`---\n${field}\n---\nbody`, 'invalid.md'));
});
