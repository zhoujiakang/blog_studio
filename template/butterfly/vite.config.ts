import { defineConfig } from 'vite';
import vue from '@vitejs/plugin-vue';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { loadContent, locateBlog } from './scripts/content.mjs';
import { publicImages } from './scripts/public-images.mjs';
const entry = fileURLToPath(new URL('.', import.meta.url));
const layout = locateBlog(entry);
const images = path.join(
  layout.root,
  'resource/images'
);
export default defineConfig({
  root: layout.template,
  publicDir: false,
  base: './',
  server: {
    fs: {
      strict: true,
      allow: [layout.template],
      deny: [
        '.env', '.env.*', '*.{crt,pem,key,p12,pfx,cer,der}',
        '.npmrc', '.yarnrc.yml', '**/.git/**', '**/blog.json',
        '**/template.json', '**/resource/**', '**/.blog-studio/**',
      ],
    },
  },
  build: { outDir: path.join(layout.root, 'dist'), emptyOutDir: true },
  plugins: [
    vue(),
    {
      name: 'markdown-blog',
      resolveId(id) {
        if (id === 'virtual:blog-content') return '\0virtual:blog-content';
      },
      load(id) {
        if (id === '\0virtual:blog-content') {
          const content = loadContent(entry);
          const posts = content.posts.map((post: Record<string, unknown>) => {
            const { meta, ...publicPost } = post;
            return publicPost;
          });
          return `export default ${JSON.stringify({ ...content, posts })}`;
        }
      },
      generateBundle() {
        for (const [name, bytes] of publicImages(loadContent(entry), images))
          this.emitFile({ type: 'asset', fileName: `img/${name}`, source: bytes });
      },
      configureServer(server) {
        // Serve only whitelisted public images; drafts/notes/config never belong to the web root.
        server.middlewares.use((request, response, next) => {
          let url: string;
          try {
            url = decodeURIComponent((request.url || '/').split('?')[0]!);
          } catch {
            response.statusCode = 400;
            response.end();
            return;
          }
          if (
            [
              '/resource/',
              '/template/',
              '/.blog-studio/',
            ].some((prefix) => url.startsWith(prefix)) ||
            (url.startsWith('/@fs/') && !url.includes('/node_modules/')) ||
            ['template.json', 'blog.json'].some((name) =>
              url.endsWith('/' + name)
            )
          ) {
            response.statusCode = 403;
            response.end();
            return;
          }
          if (!url.startsWith('/img/')) {
            next();
            return;
          }
          const name = url.slice(5);
          if (
            name.split('/').some((part) => !part || part.startsWith('.')) ||
            !/\.(png|jpe?g|gif|webp|svg)$/i.test(name)
          ) {
            response.statusCode = 404;
            response.end();
            return;
          }
          try {
            const bytes = publicImages(loadContent(entry), images).find(
              ([imageName]) => imageName === name
            )?.[1];
            if (!bytes) throw Error('Image is not referenced by public content');
            const type: Record<string, string> = {
              svg: 'image/svg+xml',
              png: 'image/png',
              jpg: 'image/jpeg',
              jpeg: 'image/jpeg',
              gif: 'image/gif',
              webp: 'image/webp',
            };
            response.setHeader(
              'Content-Type',
              type[path.extname(name).slice(1).toLowerCase()]!
            );
            response.end(bytes);
          } catch {
            response.statusCode = 404;
            response.end();
          }
        });
        server.watcher.add([
          path.join(layout.root, 'blog.json'),
          path.join(layout.root, layout.resource),
          path.join(layout.template, 'template.json'),
        ]);
        server.watcher.on('all', (event, file) => {
          if (
            ['add', 'change', 'unlink'].includes(event) &&
            (file.endsWith('.md') ||
              file.endsWith('blog.json') ||
              file.endsWith('template.json') ||
              /\.(png|jpe?g|gif|webp|svg)$/i.test(file))
          ) {
            server.moduleGraph.invalidateAll();
            server.ws.send({ type: 'full-reload' });
          }
        });
      },
    },
  ],
});
