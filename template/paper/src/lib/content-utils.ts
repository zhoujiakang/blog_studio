import type { Post } from './types';

const EPOCH_PREFIX = '1970-01-01T00:00:00';

/** 统一按北京时间呈现日期；Unix epoch 视为“没有填写日期”。 */
export function formatDate(iso: string): string {
  if (!iso || iso.startsWith(EPOCH_PREFIX)) return '';
  const date = new Date(iso);
  if (Number.isNaN(date.getTime())) return '';
  const parts = new Intl.DateTimeFormat('zh-CN', {
    timeZone: 'Asia/Shanghai',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).formatToParts(date);
  const lookup = new Map(parts.map((part) => [part.type, part.value]));
  return `${lookup.get('year') ?? ''}-${lookup.get('month') ?? ''}-${lookup.get('day') ?? ''}`;
}

export function formatLongDate(iso: string): string {
  const day = formatDate(iso);
  if (!day) return '';
  const date = new Date(iso);
  const time = new Intl.DateTimeFormat('zh-CN', {
    timeZone: 'Asia/Shanghai',
    hour: '2-digit',
    minute: '2-digit',
    hour12: false,
  }).format(date);
  return `${day} ${time}`;
}

export function yearOf(iso: string): string {
  const day = formatDate(iso);
  return day === '' ? '未标注日期' : day.slice(0, 4);
}

export interface TagStat {
  name: string;
  count: number;
}

export interface CategoryStat {
  name: string;
  count: number;
  parts: string[];
}

export function collectTags(posts: Post[]): TagStat[] {
  const counter = new Map<string, number>();
  for (const post of posts) {
    for (const tag of post.tags) {
      counter.set(tag, (counter.get(tag) ?? 0) + 1);
    }
  }
  return [...counter.entries()]
    .map(([name, count]) => ({ name, count }))
    .sort((a, b) => (b.count - a.count) || a.name.localeCompare(b.name, 'zh-CN'));
}

/** categories: ["技术/Flutter"] 是层级路径，["技术","Flutter"] 是两个独立分类。 */
export function collectCategories(posts: Post[]): CategoryStat[] {
  const counter = new Map<string, Map<string, number>>();
  for (const post of posts) {
    for (const category of post.categories) {
      const parts = category.split('/').map((part) => part.trim()).filter(Boolean);
      if (parts.length === 0) continue;
      for (let depth = 1; depth <= parts.length; depth += 1) {
        const path = parts.slice(0, depth).join('/');
        const key = parts[0];
        const bucket = counter.get(key) ?? new Map<string, number>();
        bucket.set(path, (bucket.get(path) ?? 0) + 1);
        counter.set(key, bucket);
      }
    }
  }
  const result: CategoryStat[] = [];
  for (const bucket of counter.values()) {
    for (const [name, count] of bucket) {
      result.push({ name, count, parts: name.split('/') });
    }
  }
  return result.sort((a, b) => {
    if (a.parts.length !== b.parts.length) return a.parts.length - b.parts.length;
    return a.name.localeCompare(b.name, 'zh-CN');
  });
}

export function postsInCategory(posts: Post[], category: string): Post[] {
  const target = category.trim();
  return posts.filter((post) =>
    post.categories.some((item) => item === target || item.startsWith(`${target}/`)),
  );
}

export function postsWithTag(posts: Post[], tag: string): Post[] {
  return posts.filter((post) => post.tags.includes(tag));
}
