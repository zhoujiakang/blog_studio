/**
 * 公开内容适配器。
 *
 * 只读取博客根目录下的公开内容：
 *   resource/posts/**\/*.md   正式文章
 *   resource/about.md         关于正文
 *   blog.json.site            通用信息
 *   template/<id>/template.json  主题字段
 *
 * 不读取 drafts/、notes/、备份、凭证，也不把整份配置文件发到浏览器。
 * 文件读取只在 dev/build 的 Node 进程里执行。
 */

import { existsSync, promises as fsp, readFileSync, statSync } from 'node:fs';
import path from 'node:path';

const SUPPORTED_EXTENSIONS = new Set(['.md', '.markdown']);
const DEFAULT_TIMEZONE_OFFSET = '+08:00';
const FRONT_MATTER_DELIMITER = /^(---|\+\+\+)\s*$/;
const EPOCH_ISO = new Date(0).toISOString();

/**
 * 从模板目录向上寻找 blog.json，确定博客根目录与当前活动模板。
 *
 * @param {string} templateDirectory 模板源码目录（不要求是 activate 的那一个）
 */
export function locateBlog(templateDirectory) {
  const start = path.resolve(templateDirectory);
  let dir = start;

  for (;;) {
    const blogJsonPath = path.join(dir, 'blog.json');
    if (existsSync(blogJsonPath)) {
      const blog = readJsonFile(blogJsonPath, 'blog.json');
      const site = normalizeSite(blog.site, blogJsonPath);
      const activeTemplate = sanitizeTemplateId(blog.activeTemplate, start, dir);
      return {
        blogRoot: dir,
        blogJsonPath,
        templateDirectory: path.join(dir, 'template', activeTemplate),
        activeTemplate,
        site,
      };
    }
    const parent = path.dirname(dir);
    if (parent === dir) {
      throw new Error(
        `未能定位博客根目录：从 ${start} 向上查找均未发现 blog.json。` +
          '模板必须安装在博客的 template/<id>/ 目录内。',
      );
    }
    dir = parent;
  }
}

/**
 * 读取全部公开内容，形状与 DEVELOPMENT.md 6.3 一致。
 *
 * @param {string} templateDirectory
 */
export function loadContent(templateDirectory) {
  const location = locateBlog(templateDirectory);
  const { blogRoot, site } = location;
  const postsDirectory = path.join(blogRoot, 'resource', 'posts');
  const aboutPath = path.join(blogRoot, 'resource', 'about.md');

  const posts = readPosts(postsDirectory).sort((a, b) => {
    if (a.date !== b.date) return a.date < b.date ? 1 : -1;
    return a.id < b.id ? -1 : a.id > b.id ? 1 : 0;
  });

  return {
    location,
    content: {
      site,
      posts,
      about: String(readOptionalFile(aboutPath) ?? ''),
      theme: loadThemeFields(location.templateDirectory),
    },
  };
}

/**
 * 读取主题字段，取值顺序为 value ?? default。
 *
 * @param {string} templateSourceDirectory template.json 所在目录
 */
export function loadThemeFields(templateSourceDirectory) {
  const templateJsonPath = path.join(templateSourceDirectory, 'template.json');
  if (!existsSync(templateJsonPath)) {
    return {};
  }
  const manifest = readJsonFile(templateJsonPath, 'template.json');
  const fields = Array.isArray(manifest.fields) ? manifest.fields : [];
  const theme = {};
  for (const field of fields) {
    if (!field || typeof field.key !== 'string' || !field.key) continue;
    const value = typeof field.value === 'string' ? field.value : undefined;
    const fallback = typeof field.default === 'string' ? field.default : '';
    theme[field.key] = value ?? fallback;
  }
  return theme;
}

/**
 * 解析单篇文章。不公开的文章返回 null。
 *
 * @param {string} markdown 含 Front Matter 的原文
 * @param {string} relativeFilename 相对 resource/posts 的路径，用作缺省 ID
 */
export function parsePost(markdown, relativeFilename) {
  const raw = stripBom(String(markdown ?? ''));
  const { meta, body } = splitFrontMatter(raw, relativeFilename);

  if (meta.published === false || meta.draft === true) return null;

  const fallbackId = toSlugFromFilename(relativeFilename);
  const id = normalizeSlug(meta.slug, fallbackId, relativeFilename);
  const date = normalizeDate(meta.date, relativeFilename);
  const updated = meta.updated == null || meta.updated === ''
    ? date
    : normalizeDate(meta.updated, relativeFilename);

  return {
    id,
    title: firstNonEmpty(readString(meta.title, 'title', relativeFilename), fallbackId),
    body,
    date,
    updated,
    tags: readStringList(meta.tags, 'tags', relativeFilename),
    categories: readStringList(meta.categories, 'categories', relativeFilename),
    summary: readSummary(meta.description, relativeFilename),
    cover: readString(meta.cover, 'cover', relativeFilename) ?? '',
  };
}

/* ------------------------------ Front Matter ------------------------------ */

function splitFrontMatter(raw, filename) {
  const lines = raw.split(/\r?\n/);
  let index = 0;
  // 允许前置空行，定位起始分隔符。
  while (index < lines.length && lines[index].trim() === '') index += 1;
  if (index >= lines.length || !FRONT_MATTER_DELIMITER.test(lines[index].trim())) {
    return { meta: {}, body: raw.trim() };
  }
  const opening = lines[index].trim();
  const block = [];
  index += 1;
  let closed = false;
  while (index < lines.length) {
    const line = lines[index];
    if (FRONT_MATTER_DELIMITER.test(line.trim()) && line.trim() === opening) {
      closed = true;
      index += 1;
      break;
    }
    block.push(line);
    index += 1;
  }
  if (!closed) {
    throw new Error(`文章 ${filename} 的 Front Matter 没有闭合分隔符。`);
  }
  return { meta: parseFrontMatterBlock(block, filename), body: lines.slice(index).join('\n').trim() };
}

/**
 * 极简 YAML 子集解析器，覆盖 DEVELOPMENT.md 6.2 声明的字段类型：
 * 带引号或无引号的标量、布尔、行内数组 ["a", "b"]。
 * 其他结构会明确报错，而不是静默忽略。
 */
function parseFrontMatterBlock(lines, filename) {
  const result = Object.create(null);
  let pendingKey = null;
  let pendingIndent = 0;

  for (const rawLine of lines) {
    if (rawLine.trim() === '' || rawLine.trimStart().startsWith('#')) continue;
    const indent = rawLine.length - rawLine.trimStart().length;
    const line = rawLine.trim();

    if (pendingKey !== null) {
      const isSequenceItem = /^-\s+/.test(line) && indent > pendingIndent;
      const isNestedKey = indent > pendingIndent && line.includes(':');
      if (isSequenceItem || isNestedKey) {
        throw new Error(
          `文章 ${filename} 的 Front Matter 使用了不受支持的嵌套结构（字段 ${pendingKey}）。` +
            '支持的写法请见 DEVELOPMENT.md 6.2。',
        );
      }
      pendingKey = null;
    }

    const separator = line.indexOf(':');
    if (separator <= 0) {
      throw new Error(`文章 ${filename} 的 Front Matter 无法解析：${line}`);
    }
    const key = line.slice(0, separator).trim();
    const rawValue = line.slice(separator + 1).trim();
    result[key] = parseScalar(key, rawValue, filename);
    pendingKey = key;
    pendingIndent = indent;
  }
  return result;
}

function parseScalar(key, rawValue, filename) {
  if (rawValue === '') return null;
  if (rawValue === 'true') return true;
  if (rawValue === 'false') return false;
  if (rawValue === 'null' || rawValue === '~') return null;
  if (rawValue.startsWith('[')) {
    if (!rawValue.endsWith(']')) {
      throw new Error(`文章 ${filename} 的 Front Matter 字段 ${key} 数组没有闭合。`);
    }
    const inner = rawValue.slice(1, -1).trim();
    if (inner === '') return [];
    return splitInlineList(inner, key, filename).map((item) => unquote(item));
  }
  if (rawValue.startsWith('{')) {
    throw new Error(`文章 ${filename} 的 Front Matter 字段 ${key} 使用了不受支持的对象写法。`);
  }
  return unquote(rawValue);
}

/** 按逗号切分行内数组，忽略引号内的逗号。 */
function splitInlineList(inner, key, filename) {
  const items = [];
  let buffer = '';
  let quote = null;
  for (const char of inner) {
    if (quote) {
      buffer += char;
      if (char === quote) quote = null;
      continue;
    }
    if (char === '"' || char === "'") {
      quote = char;
      buffer += char;
      continue;
    }
    if (char === ',') {
      items.push(buffer.trim());
      buffer = '';
      continue;
    }
    buffer += char;
  }
  if (quote) {
    throw new Error(`文章 ${filename} 的 Front Matter 字段 ${key} 引号没有闭合。`);
  }
  items.push(buffer.trim());
  return items.filter((item) => item !== '');
}

function unquote(value) {
  const text = String(value).trim();
  if (text.length >= 2) {
    const first = text[0];
    const last = text[text.length - 1];
    if ((first === '"' && last === '"') || (first === "'" && last === "'")) {
      return text.slice(1, -1);
    }
  }
  return text;
}

/* -------------------------------- 字段规整 -------------------------------- */

function readString(value, key, filename) {
  if (value === null || value === undefined) return '';
  if (typeof value === 'number' || typeof value === 'boolean') {
    throw new Error(`文章 ${filename} 的 Front Matter 字段 ${key} 需要是字符串。`);
  }
  if (typeof value !== 'string') {
    throw new Error(`文章 ${filename} 的 Front Matter 字段 ${key} 类型不受支持。`);
  }
  return value.trim();
}

function readStringList(value, key, filename) {
  if (value === null || value === undefined) return [];
  if (typeof value === 'string') {
    const single = value.trim();
    return single === '' ? [] : [single];
  }
  if (!Array.isArray(value)) {
    throw new Error(`文章 ${filename} 的 Front Matter 字段 ${key} 需要是字符串数组。`);
  }
  const seen = new Set();
  const result = [];
  for (const item of value) {
    if (item === null || item === undefined) continue;
    if (typeof item !== 'string') {
      throw new Error(`文章 ${filename} 的 Front Matter 字段 ${key} 含有非字符串项。`);
    }
    const text = item.trim();
    if (text === '' || seen.has(text)) continue;
    seen.add(text);
    result.push(text);
  }
  return result;
}

/** 摘要只来自显式 description，缺省、空或纯空白一律隐藏。 */
function readSummary(value, filename) {
  if (value === null || value === undefined) return '';
  if (typeof value !== 'string') {
    throw new Error(`文章 ${filename} 的 Front Matter 字段 description 需要是字符串。`);
  }
  return value.trim();
}

function normalizeSlug(value, fallback, filename) {
  const slug = typeof value === 'string' ? value.trim() : '';
  if (slug === '') return fallback;
  if (/[\\/]/.test(slug) || slug === '.' || slug === '..') {
    throw new Error(`文章 ${filename} 的 slug 不能包含路径分隔符或保留值：${slug}`);
  }
  return slug;
}

function toSlugFromFilename(relativeFilename) {
  const normalized = relativeFilename.split(path.sep).join('/');
  const withoutExtension = normalized.replace(/\.(md|markdown)$/i, '');
  return withoutExtension.split('/').filter(Boolean).join('/');
}

/**
 * 日期解析：本地无时区的日期按 +08:00 解释，带时区的按其自身时区解释。
 * 无日期使用 Unix epoch，绝不使用当前时间编造日期。非法输入报错。
 */
function normalizeDate(value, filename) {
  if (value === null || value === undefined || value === '') return EPOCH_ISO;
  if (value instanceof Date) {
    if (Number.isNaN(value.getTime())) {
      throw new Error(`文章 ${filename} 的日期无效。`);
    }
    return value.toISOString();
  }
  if (typeof value !== 'string' && typeof value !== 'number') {
    throw new Error(`文章 ${filename} 的日期必须是字符串。`);
  }
  const source = typeof value === 'number' ? String(value) : value.trim();
  const iso = toIsoString(source);
  if (!iso) {
    throw new Error(
      `文章 ${filename} 的日期无法解析：${source}。` +
        `建议使用 "YYYY-MM-DD HH:mm:ss" 或带时区的 ISO 字符串。`,
    );
  }
  const parsed = new Date(iso);
  if (Number.isNaN(parsed.getTime())) {
    throw new Error(`文章 ${filename} 的日期无效：${source}`);
  }
  return parsed.toISOString();
}

function toIsoString(source) {
  const match = source.match(
    /^(\d{4})-(\d{2})-(\d{2})(?:[T ](\d{2}):(\d{2})(?::(\d{2}))?(?:\.(\d{1,3})\d*)?)?\s*(Z|[+-]\d{2}:?\d{2})?$/,
  );
  if (!match) return null;
  const [, year, month, day, hour = '00', minute = '00', second = '00', , zone = ''] = match;
  const datePart = `${year}-${month}-${day}`;
  const timePart = `${hour}:${minute}:${second}`;
  if (zone === '') return `${datePart}T${timePart}${DEFAULT_TIMEZONE_OFFSET}`;
  if (zone === 'Z') return `${datePart}T${timePart}Z`;
  const normalizedZone = zone.includes(':') ? zone : `${zone.slice(0, 3)}:${zone.slice(3)}`;
  return `${datePart}T${timePart}${normalizedZone}`;
}

/* -------------------------------- 目录读取 -------------------------------- */

function readPosts(postsDirectory) {
  if (!existsSync(postsDirectory)) return [];
  const files = walkMarkdown(postsDirectory, postsDirectory);
  const posts = [];
  const seenIds = new Map();

  for (const file of files) {
    const absolute = path.join(postsDirectory, file);
    const source = readFileSync(absolute, 'utf8');
    const post = parsePost(source, file);
    if (!post) continue;
    const previous = seenIds.get(post.id);
    if (previous) {
      throw new Error(
        `文章地址重复：${post.id}\n  1. ${previous}\n  2. ${file}\n` +
          '请修改其中一篇的 slug 字段。',
      );
    }
    seenIds.set(post.id, file);
    posts.push(post);
  }
  return posts;
}

/** 递归收集 posts 下的 Markdown，跳过隐藏项与符号链接。 */
function walkMarkdown(directory, rootDirectory) {
  const collected = [];
  let entries;
  try {
    entries = fsp === undefined ? [] : require('node:fs').readdirSync(directory, { withFileTypes: true });
  } catch {
    return collected;
  }
  for (const entry of entries) {
    if (entry.name.startsWith('.')) continue;
    const absolute = path.join(directory, entry.name);
    let stats;
    try {
      stats = statSync(absolute);
    } catch {
      continue;
    }
    if (stats.isSymbolicLink()) continue;
    if (stats.isDirectory()) {
      collected.push(...walkMarkdown(absolute, rootDirectory));
      continue;
    }
    if (!stats.isFile()) continue;
    if (!SUPPORTED_EXTENSIONS.has(path.extname(entry.name).toLowerCase())) continue;
    collected.push(path.relative(rootDirectory, absolute).split(path.sep).join('/'));
  }
  return collected;
}

function readOptionalFile(absolutePath) {
  if (!existsSync(absolutePath)) return null;
  const stats = statSync(absolutePath);
  if (!stats.isFile() || stats.isSymbolicLink()) return null;
  return readFileSync(absolutePath, 'utf8');
}

function readJsonFile(absolutePath, label) {
  let source;
  try {
    source = readFileSync(absolutePath, 'utf8');
  } catch (error) {
    throw new Error(`无法读取 ${label}：${absolutePath}（${error.message}）`);
  }
  try {
    return JSON.parse(source);
  } catch (error) {
    throw new Error(`${label} 不是合法的 JSON：${absolutePath}（${error.message}）`);
  }
}

function normalizeSite(site) {
  const source = site && typeof site === 'object' ? site : {};
  return {
    title: readSiteField(source.title, '我的博客'),
    subtitle: readSiteField(source.subtitle, ''),
    author: readSiteField(source.author, ''),
    description: readSiteField(source.description, ''),
    avatar: readSiteField(source.avatar, ''),
  };
}

function readSiteField(value, fallback) {
  return typeof value === 'string' ? value.trim() : fallback;
}

function sanitizeTemplateId(value, fallbackDirectory, blogRoot) {
  if (typeof value === 'string' && value.trim() !== '') {
    const id = value.trim();
    if (/^[a-zA-Z0-9\u4e00-\u9fa5][a-zA-Z0-9_\u4e00-\u9fa5-]*$/.test(id)) {
      return id;
    }
    return 'paper';
  }
  const relative = path.relative(path.join(blogRoot, 'template'), fallbackDirectory);
  if (relative && !relative.startsWith('..') && relative !== '') return relative.split(path.sep)[0];
  return 'paper';
}

function stripBom(text) {
  return text.charCodeAt(0) === 0xfeff ? text.slice(1) : text;
}

function firstNonEmpty(...values) {
  for (const value of values) {
    if (typeof value === 'string' && value.trim() !== '') return value.trim();
  }
  return '';
}

export { EPOCH_ISO };
