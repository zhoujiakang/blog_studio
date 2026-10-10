import { watch } from 'node:fs';
import { promises as fsp } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import vue from '@vitejs/plugin-vue';
import { defineConfig, type Plugin, type ViteDevServer } from 'vite';

import { loadContent } from './scripts/content.mjs';
import { collectPublicImages, matchWhitelistedImage } from './scripts/public-images.mjs';

const VIRTUAL_MODULE_ID = 'virtual:blog-content';
const RESOLVED_VIRTUAL_MODULE_ID = `\0${VIRTUAL_MODULE_ID}`;

/** 模板源码目录，同时也是 Vite 的 root。dev/build 都从此处运行。 */
const templateRoot = path.dirname(fileURLToPath(import.meta.url));

/** dev 预览必须拒绝的路径，避免把整个博客根目录暴露给浏览器。 */
const DENIED_PREFIXES = ['/resource/', '/template/', '/.blog-studio/', '/drafts/', '/notes/'];
const DENIED_FILES = new Set([
  '/blog.json',
  '/template.json',
  '/package.json',
  '/package-lock.json',
  '/.env',
  '/.npmrc',
  '/.gitconfig',
]);
const DENIED_SUFFIXES = ['.md.raw', '.bak', '.sqlite', '.sqlite3', '.pem', '.key'];

const MIME_TYPES = new Map<string, string>([
  ['.png', 'image/png'],
  ['.jpg', 'image/jpeg'],
  ['.jpeg', 'image/jpeg'],
  ['.gif', 'image/gif'],
  ['.webp', 'image/webp'],
  ['.avif', 'image/avif'],
  ['.svg', 'image/svg+xml'],
  ['.ico', 'image/x-icon'],
  ['.bmp', 'image/bmp'],
  ['.heic', 'image/heic'],
]);

interface BlogState {
  content: unknown;
  imagePaths: Map<string, string>;
}

function createBlogPlugin(): Plugin {
  let state: BlogState | null = null;
  let pending: Promise<BlogState> | null = null;
  const nativeWatchers: Array<{ close: () => void }> = [];

  async function readState(): Promise<BlogState> {
    if (state) return state;
    if (pending) return pending;
    pending = (async () => {
      const bundle = loadContent(templateRoot);
      const imagePaths = await collectPublicImages(bundle);
      const next: BlogState = { content: bundle.content, imagePaths };
      state = next;
      return next;
    })();
    try {
      return await pending;
    } finally {
      pending = null;
    }
  }

  function invalidate() {
    state = null;
  }

  return {
    name: 'paper:blog-content',

    resolveId(id) {
      if (id === VIRTUAL_MODULE_ID) return RESOLVED_VIRTUAL_MODULE_ID;
      return null;
    },

    async load(id) {
      if (id !== RESOLVED_VIRTUAL_MODULE_ID) return null;
      const current = await readState();
      return `export default ${JSON.stringify(current.content)};`;
    },

    configureServer(server: ViteDevServer) {
      // 前置守卫：禁止任何指向博客私有区域或敏感文件的请求。
      server.middlewares.use((req, res, next) => {
        const request = req.url ?? '/';
        const decoded = safeDecode(request.split('?')[0]);
        if (decoded === null || !isRequestAllowed(decoded)) {
          res.statusCode = 403;
          res.setHeader('Content-Type', 'text/plain; charset=utf-8');
          res.end('403 Forbidden');
          return;
        }
        next();
      });

      // 共享图片同样需要前置处理：否则会被 Vite 的 SPA fallback 重写成 index.html。
      server.middlewares.use(async (req, res, next) => {
        const urlPath = safeDecode((req.url ?? '').split('?')[0]);
        if (!urlPath || !urlPath.startsWith('/img/')) {
          next();
          return;
        }
        try {
          const current = await readState();
          const absolute = matchWhitelistedImage(current.imagePaths, urlPath);
          if (!absolute) {
            res.statusCode = 404;
            res.setHeader('Content-Type', 'text/plain; charset=utf-8');
            res.end('404 Not Found');
            return;
          }
          const file = await fsp.readFile(absolute);
          res.statusCode = 200;
          res.setHeader(
            'Content-Type',
            MIME_TYPES.get(path.extname(absolute).toLowerCase()) ?? 'application/octet-stream',
          );
          res.setHeader('Cache-Control', 'no-cache');
          res.end(file);
        } catch {
          next();
        }
      });

      startWatching(server);
    },

    async generateBundle() {
      const current = await readState();
      for (const [publicPath, absolute] of current.imagePaths) {
        this.emitFile({
          type: 'asset',
          fileName: publicPath.replace(/^\//, ''),
          source: await fsp.readFile(absolute),
        });
      }
    },

    buildEnd() {
      for (const watcher of nativeWatchers) watcher.close();
      nativeWatchers.length = 0;
    },
  };

  function startWatching(server: ViteDevServer) {
    let locationRoot: string;
    try {
      locationRoot = loadContent(templateRoot).location.blogRoot;
    } catch {
      return;
    }

    const targets = [
      locationRoot,
      path.join(locationRoot, 'blog.json'),
      path.join(locationRoot, 'resource'),
      path.join(locationRoot, 'template'),
    ];

    for (const target of targets) {
      server.watcher.add(target);
    }

    let timer: NodeJS.Timeout | null = null;
    const scheduleReload = () => {
      if (timer) clearTimeout(timer);
      timer = setTimeout(() => {
        timer = null;
        invalidate();
        // 虚拟模块没有对应文件，必须显式清除 Vite 的变换缓存。
        const moduleNode = server.moduleGraph.getModuleById(RESOLVED_VIRTUAL_MODULE_ID);
        if (moduleNode) server.moduleGraph.invalidateModule(moduleNode);
        server.ws.send({ type: 'full-reload' });
      }, 200);
    };

    // 资源目录位于 Vite root 之外，额外用原生监听保证变更能被发现。
    for (const target of [path.join(locationRoot, 'resource'), path.join(locationRoot, 'blog.json'), path.join(locationRoot, 'template')]) {
      try {
        const watcher = watch(target, { recursive: true }, scheduleReload);
        nativeWatchers.push(watcher);
      } catch {
        /* 目录不存在时跳过 */
      }
    }
    server.watcher.on('all', scheduleReload);
  }
}

function isRequestAllowed(urlPath: string): boolean {
  if (urlPath.includes('..')) return false;
  if (urlPath.startsWith('/@fs/')) {
    // 只允许 Vite 自身必要的源文件访问，此处的目标是模板目录内的源码。
    return true;
  }
  for (const prefix of DENIED_PREFIXES) {
    if (urlPath === prefix.slice(0, -1) || urlPath.startsWith(prefix)) return false;
  }
  if (DENIED_FILES.has(urlPath)) return false;
  if (urlPath.startsWith('/.env')) return false;
  if (DENIED_SUFFIXES.some((suffix) => urlPath.endsWith(suffix))) return false;
  return true;
}

function safeDecode(value: string): string | null {
  try {
    return decodeURIComponent(value);
  } catch {
    return null;
  }
}

export default defineConfig({
  base: './',
  publicDir: false,
  plugins: [vue(), createBlogPlugin()],
  server: {
    strictPort: true,
    fs: {
      strict: true,
      // 只开放模板目录；绝不把博客根目录整体加入浏览器可访问范围。
      allow: [templateRoot],
      deny: ['.env', '.env.*', '**/.git/**'],
    },
  },
  build: {
    outDir: 'dist',
    assetsDir: 'assets',
    sourcemap: false,
    cssCodeSplit: true,
    chunkSizeWarningLimit: 900,
  },
});
