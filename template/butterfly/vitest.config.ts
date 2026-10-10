import { defineConfig } from 'vitest/config';
import vue from '@vitejs/plugin-vue';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { loadContent } from './scripts/content.mjs';

// Unit tests prepare a current-format blog; the theme source itself is not a blog.
const root = fs.mkdtempSync(path.join(os.tmpdir(), 'inkjian-theme-test-'));
let content;
try {
  const config = JSON.parse(fs.readFileSync(new URL('./template.json', import.meta.url), 'utf8'));
  fs.mkdirSync(path.join(root, 'template/butterfly'), { recursive: true });
  fs.mkdirSync(path.join(root, 'resource'), { recursive: true });
  fs.writeFileSync(path.join(root, 'blog.json'), JSON.stringify({ formatVersion: 2, activeTemplate: 'butterfly', site: config.site }));
  fs.writeFileSync(path.join(root, 'template/butterfly/template.json'), JSON.stringify(config));
  fs.cpSync(new URL('../../test/fixtures/butterfly/posts', import.meta.url), path.join(root, 'resource/posts'), { recursive: true });
  fs.copyFileSync(new URL('../../test/fixtures/butterfly/about.md', import.meta.url), path.join(root, 'resource/about.md'));
  content = loadContent(root);
} finally {
  fs.rmSync(root, { recursive: true, force: true });
}
export default defineConfig({
  plugins: [vue(), {
    name: 'test-blog-content',
    resolveId(id) { if (id === 'virtual:blog-content') return '\0virtual:blog-content'; },
    load(id) { if (id === '\0virtual:blog-content') return `export default ${JSON.stringify(content)}`; },
  }],
  test: { environment: 'jsdom', include: ['tests/**/*.test.ts'] },
});
