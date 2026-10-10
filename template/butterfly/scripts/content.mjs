import fs from 'node:fs';
import path from 'node:path';
import matter from 'gray-matter';
import { parse as parseYaml } from 'yaml';

const list = (value) => {
  if (value == null) return [];
  if (!Array.isArray(value) || value.some((item) => typeof item !== 'string'))
    throw Error('标签和分类必须是字符串数组');
  return value;
};
const date = (value, fallback) => {
  if (value == null) return fallback;
  if (typeof value !== 'string') throw Error('日期必须是字符串');
  let normalized = value;
  // The editor stores local dates without a time zone; the blog uses +08:00.
  if (/^\d{4}-\d{2}-\d{2}(?:[ T]\d{2}:\d{2}(?::\d{2})?)?$/.test(normalized))
    normalized =
      normalized.length === 10
        ? `${normalized}T00:00:00+08:00`
        : `${normalized.replace(' ', 'T')}+08:00`;
  if (!Number.isFinite(Date.parse(normalized)))
    throw new Error(`无效日期：${normalized}`);
  return new Date(normalized).toISOString();
};
export function parsePost(source, filename) {
  if (
    /^---\r?\n/.test(source) &&
    !/^---\s*$/m.test(source.slice(source.indexOf('\n') + 1))
  )
    throw new Error(`${filename}: Front Matter 缺少结束标记`);
  const { data, content } = matter(source, { engines: { yaml: parseYaml } });
  if (!data || typeof data !== 'object' || Array.isArray(data))
    throw new Error(`${filename}: Front Matter 必须是对象`);
  for (const key of ['title', 'date', 'updated', 'description', 'cover', 'slug'])
    if (key in data && typeof data[key] !== 'string') throw Error(`${key} 必须是字符串`);
  for (const key of ['published', 'draft'])
    if (key in data && typeof data[key] !== 'boolean') throw Error(`${key} 必须是布尔值`);
  list(data.tags);
  list(data.categories);
  if (data.published === false || data.draft === true)
    return null;
  const created = date(data.date, '1970-01-01T00:00:00.000Z');
  const stem = filename.replace(/\.md$/i, '').replaceAll('\\', '/');
  const body = content.trim();
  const summary = String(data.description || '').trim();
  return {
    id: String(data.slug ?? stem),
    title: String(data.title ?? path.basename(stem)),
    body,
    date: created,
    updated: date(data.updated, created),
    tags: list(data.tags),
    categories: list(data.categories),
    summary,
    cover: String(data.cover ?? ''),
    meta: data,
  };
}
function collect(directory, prefix = '') {
  if (!fs.existsSync(directory)) return [];
  return fs.readdirSync(directory, { withFileTypes: true }).flatMap((entry) => {
    if (entry.isSymbolicLink() || entry.name.startsWith('.')) return [];
    const file = path.join(directory, entry.name),
      relative = `${prefix}${entry.name}`;
    if (entry.isDirectory()) return collect(file, `${relative}/`);
    return entry.isFile() && /\.md$/i.test(entry.name)
      ? [[relative, fs.readFileSync(file, 'utf8')]]
      : [];
  });
}
export function locateBlog(root) {
  let current = path.resolve(root);
  while (true) {
    const marker = path.join(current, 'blog.json');
    if (fs.existsSync(marker)) {
      const manifest = JSON.parse(fs.readFileSync(marker, 'utf8'));
      if (
        !manifest || manifest.formatVersion !== 2 || typeof manifest.activeTemplate !== 'string' ||
        !/^[a-zA-Z0-9\u4e00-\u9fff][a-zA-Z0-9_\u4e00-\u9fff-]*$/.test(
          manifest.activeTemplate
        )
      )
        throw Error('博客资源格式无效');
      return {
        root: current,
        template: path.join(
          current,
          'template',
          manifest.activeTemplate
        ),
        resource: 'resource',
        site: manifest.site ?? {},
      };
    }
    const parent = path.dirname(current);
    if (parent === current)
      throw Error('缺少 blog.json；请先创建 blog.json + resource/ + template/ 博客目录');
    current = parent;
  }
}
export function loadContent(inputRoot) {
  const layout = locateBlog(inputRoot),
    root = layout.root;

  const templatePath = path.join(layout.template, 'template.json');
  const templateConfig = fs.existsSync(templatePath)
    ? JSON.parse(fs.readFileSync(templatePath, 'utf8'))
    : null;
  if (!templateConfig) throw Error('缺少模板配置 template.json');
  const config = {
    title: '拾笺 InkJian', subtitle: '', description: '', author: '', avatar: '',
    ...layout.site,
  };
  const keys = ['title', 'subtitle', 'description', 'author', 'avatar'];
  for (const key of keys)
    if (typeof config[key] !== 'string') throw new Error(`站点 ${key} 必须是文字`);
  const site = Object.fromEntries(keys.map((key) => [key, config[key]]));
  const posts = collect(
    path.join(root, 'resource/posts')
  )
    .map(([name, source]) => parsePost(source, name))
    .filter(Boolean)
    .sort((a, b) => b.date.localeCompare(a.date));
  const ids = new Set();
  for (const post of posts) {
    if (ids.has(post.id)) throw new Error(`文章地址重复：${post.id}`);
    ids.add(post.id);
  }
  const aboutPath = path.join(
    root,
    'resource/about.md'
  );
  const about = fs.existsSync(aboutPath)
    ? matter(fs.readFileSync(aboutPath, 'utf8'), { engines: { yaml: parseYaml } }).content
    : '';
  let theme = {};
  const configPath = path.join(layout.template, 'template.json');
  if (fs.existsSync(configPath)) {
    const configuration = JSON.parse(fs.readFileSync(configPath, 'utf8'));
    if (configuration.formatVersion !== 1 || !Array.isArray(configuration.fields))
      throw Error('模板配置格式不支持');
    for (const field of configuration.fields) {
      if (!['text', 'image', 'color'].includes(field.type)) continue;
      const value = field.value ?? field.default ?? '';
      if (typeof value !== 'string') throw Error(`模板配置 ${field.key} 必须是文字`);
      if (field.type === 'color' && !/^#[0-9a-fA-F]{6}$/.test(value))
        throw Error(`无效颜色：${field.key}`);
      if (
        field.type === 'image' &&
        value &&
        (!/^\/img\/[\w/.-]+$/.test(value) || value.split('/').includes('..'))
      )
        throw Error(`无效图片路径：${field.key}`);
      theme[field.key] = value;
    }
  }
  return { site, posts, about, theme };
}
