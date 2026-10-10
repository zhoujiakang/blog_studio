import { defineConfig } from 'vite';
import { writeFileSync } from 'node:fs';
export default defineConfig({
  base: './',
  define: {'process.env.NODE_ENV': JSON.stringify('production')},
  plugins: [{name: 'local-html', closeBundle() {
    writeFileSync('../../assets/editor/index.html', `<!doctype html><html lang="zh-CN"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data: blob:; font-src 'self' data:; connect-src 'none'"><link rel="stylesheet" href="./index.css"><title>Blog Studio 编辑器</title></head><body><main id="editor"></main><script src="./editor.js"></script></body></html>`);
  }}],
  build: {
    outDir: '../../assets/editor',
    emptyOutDir: true,
    assetsInlineLimit: 0,
    lib: {entry: 'src/main.js', name: 'StudioEditor', formats: ['iife'], fileName: () => 'editor.js', cssFileName: 'index'},
    rollupOptions: {output: {assetFileNames: '[name][extname]'}},
  },
});
