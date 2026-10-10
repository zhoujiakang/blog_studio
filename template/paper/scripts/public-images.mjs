/**
 * 共享图片白名单。
 *
 * 只有被公开内容真正引用的图片才会进入白名单：
 *   resource/images/ 下的文件 → dev 映射为 /img/<name>，build 输出为 img/<name>。
 *
 * 绝不整体复制 resource/images/，否则只被草稿或小记使用的图片会泄漏。
 */

import { promises as fsp } from 'node:fs';
import path from 'node:path';

const IMAGE_ROOT_PREFIX = '/img/';

/** Markdown 图片：![alt](/img/a.png "title") */
const MARKDOWN_IMAGE = /!\[[^\]]*\]\(\s*<?([^()\s>]+)>?(?:\s+[^)]*)?\)/g;
/** Markdown 链接（含引用式的定义行）：[x]: /img/a.png */
const MARKDOWN_LINK = /(?:^|\s)!?\[[^\]]*\]\s*:\s*<?([^()\s>]+)>?/g;
/** HTML 属性中的图片引用：<img src="/img/a.png">、url('/img/a.png') */
const HTML_ATTRIBUTE = /(?:src|href|data-src|poster)\s*=\s*["']([^"']+)["']/g;
const HTML_URL = /url\(\s*["']?([^"')]+)["']?\s*\)/g;

/**
 * 收集白名单图片。
 *
 * @param {{ location: { blogRoot: string }, content: any }} bundle loadContent 的结果
 * @returns {Promise<Map<string, string>>} /img/<name> → 磁盘绝对路径
 */
export async function collectPublicImages(bundle) {
  const { blogRoot } = bundle.location;
  const { posts, about, site, theme } = bundle.content;
  const imagesDirectory = path.join(blogRoot, 'resource', 'images');

  const references = new Set();
  for (const post of posts) {
    collectReferences(post.body, references);
    addPublicPath(post.cover, references);
  }
  collectReferences(about, references);
  addPublicPath(site.avatar, references);
  for (const value of Object.values(theme)) {
    if (typeof value === 'string') addPublicPath(value, references);
  }

  const result = new Map();
  for (const publicPath of references) {
    const absolute = resolveInsideImages(imagesDirectory, publicPath);
    if (!absolute) continue;
    // eslint-disable-next-line no-await-in-loop
    if (!(await isReadableFile(absolute))) continue;
    result.set(publicPath, absolute);
  }
  return result;
}

function collectReferences(markdown, sink) {
  const source = typeof markdown === 'string' ? markdown : '';
  for (const pattern of [MARKDOWN_IMAGE, MARKDOWN_LINK, HTML_ATTRIBUTE, HTML_URL]) {
    pattern.lastIndex = 0;
    let match;
    while ((match = pattern.exec(source)) !== null) {
      addPublicPath(match[1], sink);
    }
  }
}

/** 只接受以 /img/ 开头、不含 .. 的相对路径。 */
function addPublicPath(value, sink) {
  if (typeof value !== 'string') return;
  const candidate = decodeUriSafe(value.trim().split(/[?#]/)[0]);
  if (!candidate || !candidate.startsWith(IMAGE_ROOT_PREFIX)) return;
  const name = candidate.slice(IMAGE_ROOT_PREFIX.length);
  if (name === '' || name.startsWith('/') || name.endsWith('/')) return;
  if (!/^[A-Za-z0-9._\u4e00-\u9fa5/-]+$/.test(name)) return;
  if (name.split('/').some((segment) => segment === '' || segment === '.' || segment === '..')) return;
  sink.add(`${IMAGE_ROOT_PREFIX}${name}`);
}

function resolveInsideImages(imagesDirectory, publicPath) {
  const name = publicPath.slice(IMAGE_ROOT_PREFIX.length);
  const segments = name.split('/');
  const absolute = path.resolve(imagesDirectory, ...segments);
  const root = path.resolve(imagesDirectory);
  if (absolute !== root && !absolute.startsWith(`${root}${path.sep}`)) return null;
  return absolute;
}

async function isReadableFile(absolute) {
  try {
    const stats = await fsp.stat(absolute);
    return stats.isFile();
  } catch {
    return false;
  }
}

function decodeUriSafe(value) {
  try {
    return decodeURIComponent(value);
  } catch {
    return value;
  }
}

/**
 * dev 中间件专用：把请求 URL 换算为白名单中的磁盘路径，越界返回 null。
 *
 * @param {Map<string, string>} whitelist
 * @param {string} urlPath 形如 /img/sub/a.png
 */
export function matchWhitelistedImage(whitelist, urlPath) {
  const decoded = decodeUriSafe(urlPath.split('?')[0]);
  return whitelist.get(decoded) ?? null;
}
