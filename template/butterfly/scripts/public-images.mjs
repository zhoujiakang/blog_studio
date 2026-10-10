import fs from 'node:fs';
import path from 'node:path';
import { marked } from 'marked';

export function publicImages(content, directory) {
  const names = new Set();
  const add = (value) => {
    if (typeof value !== 'string' || !/^\/?img\//.test(value)) return;
    let name;
    try { name = decodeURIComponent(value.replace(/^\/?img\//, '').split(/[?#]/)[0]); }
    catch { return; }
    if (!name || name.includes('\\') || name.split('/').some((p) => !p || p.startsWith('.'))) return;
    names.add(name);
  };
  const markdown = (value) => {
    marked.walkTokens(marked.lexer(value || ''), (token) => {
      if (token.type === 'image' || token.type === 'link') add(token.href);
      if (token.type === 'html') {
        const html = token.text.replace(/<!--[\s\S]*?-->/g, '');
        for (const match of html.matchAll(/\b(?:src|href)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))/gi))
          add(match[1] ?? match[2] ?? match[3]);
      }
    });
  };
  for (const post of content.posts) { markdown(post.body); add(post.cover); }
  markdown(content.about);
  for (const value of [...Object.values(content.site), ...Object.values(content.theme)]) {
    if (typeof value !== 'string') continue;
    add(value); markdown(value);
  }
  return [...names].flatMap((name) => {
    let current = directory;
    try {
      for (const part of name.split('/')) {
        current = path.join(current, part);
        if (fs.lstatSync(current).isSymbolicLink()) throw Error('symlink');
      }
      return fs.statSync(current).isFile() && /\.(png|jpe?g|gif|webp|svg)$/i.test(name)
        ? [[name, fs.readFileSync(current)]] : [];
    } catch { return []; }
  });
}
