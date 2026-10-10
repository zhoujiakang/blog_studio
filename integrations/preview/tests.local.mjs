import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import { resolveBlog } from './layout.mjs';
import { startPreview } from './server.mjs';
const fixture = await fs.realpath(
  JSON.parse(
    await fs.readFile(new URL('../../build/test-blog.json', import.meta.url), 'utf8')
  ).root
);
const layout = await resolveBlog(fixture);
const resources = { posts: 'resource/posts', drafts: 'resource/drafts', notes: 'resource/notes' };
test('Vue preview serves public content, refreshes and blocks private files', async () => {
  const post = path.join(fixture, resources.posts, 'studio-public-check.md');
  const draft = path.join(fixture, resources.drafts, 'studio-private-check.md');
  const note = path.join(fixture, resources.notes, 'studio-private-note.md');
  await fs.mkdir(path.dirname(note), { recursive: true });
  await fs.writeFile(note, 'PRIVATE_NOTE_BODY_CHECK');
  const source =
    '---\ntitle: LOCAL_PUBLIC_CHECK\ndate: 2026-10-08 10:00:00\ncustom: PRIVATE_META_CHECK\n---\n\nPUBLIC_BODY_CHECK\n';
  await fs.writeFile(post, source);
  await fs.writeFile(draft, '---\ntitle: PRIVATE_DRAFT_CHECK\n---\nSECRET_BODY_CHECK\n');
  let preview;
  try {
    preview = await startPreview(fixture);
    assert.equal(new URL(preview.url).hostname, '127.0.0.1');
    const main = await fetch(preview.url + 'src/main.ts');
    assert.equal(main.status, 200);
    const mainSource = await main.text();
    assert.match(mainSource, /App.vue/);
    // Browser dependencies must be converted, not served from Node's CJS entry.
    assert.doesNotMatch(mainSource, /node_modules\/vue\/index\.js/);
    const vueUrl = mainSource.match(/from "([^"]*\/vue\.js[^\"]*)"/)?.[1];
    assert.ok(vueUrl, 'Vue should use a browser prebundle');
    const vueResponse = await fetch(new URL(vueUrl, preview.url));
    assert.equal(vueResponse.status, 200);
    assert.match(await vueResponse.text(), /createApp/);
    const app = await fetch(preview.url + 'src/App.vue');
    assert.equal(app.status, 200);
    assert.match(await app.text(), /blog-content/);
    const virtual = () =>
      fetch(preview.url + '@id/__x00__virtual:blog-content?t=' + Date.now()).then((r) => r.text());
    const content = await virtual();
    assert.match(content, /PUBLIC_BODY_CHECK/);
    const previewSummary = (text) => JSON.parse(
      text.split('export default ')[1].split('\n')[0].replace(/;\s*$/, '')
    ).posts.find((p) => p.title === 'LOCAL_PUBLIC_CHECK').summary;
    assert.equal(previewSummary(content), '', 'preview must not generate a summary from the body');
    for (const [fields, expected] of [
      ['description: Explicit summary\nexcerpt: Other summary', 'Explicit summary'],
      ['excerpt: Explicit excerpt', ''],
      ['description: ""\nexcerpt: Explicit excerpt', ''],
      ['description: ""\nexcerpt: ""', ''],
    ]) {
      await fs.writeFile(post, source.replace('custom: PRIVATE_META_CHECK', fields));
      await preview.refresh();
      await eventually(async () => assert.equal(previewSummary(await virtual()), expected));
    }

    assert.doesNotMatch(
      content,
      /SECRET_BODY_CHECK|PRIVATE_META_CHECK|PRIVATE_DRAFT_CHECK|PRIVATE_NOTE_BODY_CHECK/
    );
    for (const target of [
      `${layout.resource}/notes/studio-private-note.md`,
      `${layout.resource}/drafts/studio-private-check.md`,
      `${layout.resource}/about.md`,
      `${layout.template}template.json`,
      'blog.json',
      '@fs/' + fixture + '/resource/drafts/studio-private-check.md',
      '.blog-studio/backups/resource/posts/test.md',
    ]) {
      const response = await fetch(preview.url + target);
      assert.ok([403, 404].includes(response.status), `${target}: ${response.status}`);
      assert.doesNotMatch(await response.text(), /SECRET_BODY_CHECK/);
    }
    await fs.writeFile(post, source.replace('PUBLIC_BODY_CHECK', 'UPDATED_BODY_CHECK'));
    await preview.refresh();
    const refreshed = await virtual();
    await eventually(async () => assert.match(await virtual(), /UPDATED_BODY_CHECK/));
    assert.equal(previewSummary(refreshed), '');
    const stoppedUrl = preview.url;
    await preview.stop();
    preview = null;
    await assert.rejects(fetch(stoppedUrl));
  } finally {
    await preview?.stop();
    await fs.rm(post, { force: true });
    await fs.rm(draft, { force: true });
    await fs.rm(note, { force: true });
  }
});

test('dependency install refuses stale approval without changing project', async () => {
  const { spawn } = await import('node:child_process');
  const root = await fs.mkdtemp(
    path.join((await import('node:os')).tmpdir(), 'studio-install-reject-')
  );
  try {
    const packageRoot = await installFixture(root);
    await fs.writeFile(path.join(packageRoot, 'package.json'), '{"name":"test","private":true}');
    const process = spawn(globalThis.process.execPath, [
      'integrations/preview/install.mjs',
      root,
      '/usr/bin/false',
      JSON.stringify({ manifestHash: 'stale', lockHash: null }),
    ]);
    let output = '';
    process.stdout.on('data', (bytes) => (output += bytes));
    const code = await new Promise((resolve) => process.on('exit', resolve));
    assert.equal(code, 1);
    assert.match(output, /清单已变化/);
    assert.deepEqual(await fs.readdir(packageRoot), ['package.json']);
  } finally {
    await fs.rm(root, { recursive: true, force: true });
  }
});

test('cancelled installation cleans staging and preserves old dependencies', async () => {
  const { spawn } = await import('node:child_process');
  const { manifestIdentity } = await import('./probe.mjs');
  const root = await fs.mkdtemp(
    path.join((await import('node:os')).tmpdir(), 'studio-install-cancel-')
  );
  try {
    const packageRoot = await installFixture(root);
    await fs.writeFile(path.join(packageRoot, 'package.json'), '{"name":"test","private":true}');
    await fs.mkdir(path.join(packageRoot, 'node_modules'));
    await fs.writeFile(path.join(packageRoot, 'node_modules', 'keep.txt'), 'old');
    const npm = path.join(root, 'fake-npm');
    await fs.writeFile(npm, '#!/bin/sh\necho INSTALL_STARTED\nsleep 30\n');
    await fs.chmod(npm, 0o755);
    const process = spawn(globalThis.process.execPath, [
      'integrations/preview/install.mjs',
      root,
      npm,
      JSON.stringify(await manifestIdentity(root)),
    ]);
    let output = '';
    process.stdout.on('data', (bytes) => {
      output += bytes;
      if (output.includes('INSTALL_STARTED')) process.stdin.write('cancel\n');
    });
    const code = await new Promise((resolve) => process.on('exit', resolve));
    assert.equal(code, 1);
    assert.match(output, /安装已取消/);
    assert.equal(
      await fs.readFile(path.join(packageRoot, 'node_modules', 'keep.txt'), 'utf8'),
      'old'
    );
    assert.ok(
      !(await fs.readdir(packageRoot)).some((name) => name.startsWith('.studio-install-'))
    );
  } finally {
    await fs.rm(root, { recursive: true, force: true });
  }
});

test('approved real npm install passes health check without changing manifests', async () => {
  const { spawn } = await import('node:child_process');
  const { manifestIdentity, inspectDependencies } = await import('./probe.mjs');
  const root = await fs.mkdtemp(
    path.join((await import('node:os')).tmpdir(), 'studio-install-real-')
  );
  try {
    const packageRoot = await installFixture(root);
    for (const name of ['package.json', 'package-lock.json'])
      await fs.copyFile(path.join(layout.packageRoot, name), path.join(packageRoot, name));
    const identity = await manifestIdentity(root);
    const npmPath = path.join(path.dirname(globalThis.process.execPath), 'npm');
    const process = spawn(globalThis.process.execPath, [
      'integrations/preview/install.mjs',
      root,
      npmPath,
      JSON.stringify(identity),
    ]);
    let output = '';
    process.stdout.on('data', (bytes) => (output += bytes));
    process.stderr.on('data', (bytes) => (output += bytes));
    const code = await new Promise((resolve) => process.on('exit', resolve));
    assert.equal(code, 0, output.slice(-2000));
    assert.match(output, /"type":"done"/);
    assert.equal((await inspectDependencies(root)).status, 'ready');
    assert.deepEqual(await manifestIdentity(root), identity);
    assert.ok(
      !(await fs.readdir(packageRoot)).some((name) => name.startsWith('.studio-install-'))
    );
  } finally {
    await fs.rm(root, { recursive: true, force: true });
  }
});

test('shared preview refreshes About/theme/images without exposing private resources', async () => {
  const configPath = path.join(fixture, `${layout.template}template.json`);
  const aboutPath = path.join(fixture, `${layout.resource}/about.md`);
  const configOriginal = await fs.readFile(configPath),
    aboutOriginal = await fs.readFile(aboutPath);
  const image = path.join(fixture, `${layout.resource}/images/shared-check.svg`);
  let preview;
  try {
    const config = JSON.parse(configOriginal);
    config.fields.find((f) => f.key === 'themeColor').value = '#123ABC';
    config.fields.find((f) => f.key === 'backgroundImage').value =
      '/img/shared-check.svg';
    config.fields.find((f) => f.key === 'announcement').value = 'SHARED_ANNOUNCEMENT';
    await fs.writeFile(configPath, JSON.stringify(config));
    await fs.writeFile(aboutPath, '# SHARED_ABOUT_CHECK');
    await fs.writeFile(
      image,
      '<svg xmlns="http://www.w3.org/2000/svg" width="1" height="1"></svg>'
    );
    preview = await startPreview(fixture);
    const virtual = () =>
      fetch(preview.url + '@id/__x00__virtual:blog-content?t=' + Date.now()).then((r) => r.text());
    const content = await virtual();
    assert.match(content, /#123ABC/);
    assert.match(content, /SHARED_ANNOUNCEMENT/);
    assert.match(content, /SHARED_ABOUT_CHECK/);
    assert.match(content, /shared-check.svg/);
    assert.equal((await fetch(preview.url + 'img/shared-check.svg')).status, 200);
    await fs.writeFile(aboutPath, 'UPDATED_SHARED_ABOUT');
    await preview.refresh();
    await eventually(async () => assert.match(await virtual(), /UPDATED_SHARED_ABOUT/));
    for (const file of [
      `${layout.resource}/posts/welcome.md`,
      `${layout.resource}/about.md`,
      `${layout.template}template.json`,
      'blog.json',
    ])
      assert.equal((await fetch(preview.url + file)).status, 403);
  } finally {
    await preview?.stop();
    await fs.writeFile(configPath, configOriginal);
    await fs.writeFile(aboutPath, aboutOriginal);
    await fs.rm(image, { force: true });
  }
});

test('v2 switches cached local themes, keeps common site data and resolves each dependency directory', async () => {
  const markerPath = path.join(fixture, 'blog.json');
  const original = await fs.readFile(markerPath);
  const target = path.join(fixture, 'template', 'preview-alternate');
  const originalThemeConfig = await fs.readFile(
    path.join(layout.packageRoot, 'template.json')
  );
  const about = await fs.readFile(path.join(fixture, 'resource/about.md'));
  let preview;
  try {
    await fs.cp(layout.packageRoot, target, { recursive: true });
    const alternate = JSON.parse(originalThemeConfig);
    alternate.id = 'preview-alternate';
    alternate.fields.find((f) => f.key === 'announcement').value =
      'ALTERNATE_THEME_SETTING';
    await fs.writeFile(path.join(target, 'template.json'), JSON.stringify(alternate));
    const marker = JSON.parse(original);
    marker.site.title = 'COMMON_SITE_TITLE';
    await fs.writeFile(markerPath, JSON.stringify(marker));
    preview = await startPreview(fixture);
    const content = () =>
      fetch(preview.url + '@id/__x00__virtual:blog-content').then((r) => r.text());
    assert.match(await content(), /COMMON_SITE_TITLE/);
    marker.site.title = 'LIVE_COMMON_TITLE';
    await fs.writeFile(markerPath, JSON.stringify(marker));
    await preview.refresh();
    await eventually(async () => assert.match(await content(), /LIVE_COMMON_TITLE/));
    await preview.stop();
    preview = null;
    marker.activeTemplate = 'preview-alternate';
    await fs.writeFile(markerPath, JSON.stringify(marker));
    assert.equal(path.resolve((await resolveBlog(fixture)).packageRoot), target);
    preview = await startPreview(fixture);
    assert.match(await content(), /ALTERNATE_THEME_SETTING/);
    await eventually(async () => assert.match(await content(), /LIVE_COMMON_TITLE/));
    await preview.stop();
    preview = null;
    marker.activeTemplate = JSON.parse(original).activeTemplate;
    await fs.writeFile(markerPath, JSON.stringify(marker));
    preview = await startPreview(fixture);
    assert.doesNotMatch(await content(), /ALTERNATE_THEME_SETTING/);
    assert.deepEqual(
      await fs.readFile(path.join(layout.packageRoot, 'template.json')),
      originalThemeConfig
    );
    assert.deepEqual(await fs.readFile(path.join(fixture, 'resource/about.md')), about);
  } finally {
    await preview?.stop();
    await fs.writeFile(markerPath, original);
    await fs.rm(target, { recursive: true, force: true });
  }
});

async function eventually(check) {
  const deadline = Date.now() + 5000;
  while (true) {
    try { return await check(); } catch (e) {
      if (Date.now() >= deadline) throw e;
      await new Promise((resolve) => setTimeout(resolve, 100));
    }
  }
}

async function installFixture(root) {
  await fs.mkdir(path.join(root, 'resource'));
  const packageRoot = path.join(root, 'template/butterfly');
  await fs.mkdir(packageRoot, { recursive: true });
  await fs.writeFile(path.join(root, 'blog.json'), '{"formatVersion":2,"activeTemplate":"butterfly"}');
  return packageRoot;
}
