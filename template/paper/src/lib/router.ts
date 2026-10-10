import { ref, computed, type ComputedRef } from 'vue';

export type Route =
  | { name: 'home' }
  | { name: 'archive' }
  | { name: 'about' }
  | { name: 'post'; id: string }
  | { name: 'tags' }
  | { name: 'tag'; tag: string }
  | { name: 'categories' }
  | { name: 'category'; category: string }
  | { name: 'not-found'; raw: string };

const hasWindow = typeof window !== 'undefined';
const initialHash = hasWindow ? window.location.hash : '';

const currentHash = ref(initialHash);

if (hasWindow) {
  window.addEventListener('hashchange', () => {
    currentHash.value = window.location.hash;
    window.scrollTo({ top: 0 });
  });
}

function decodeSegment(value: string): string {
  try {
    return decodeURIComponent(value);
  } catch {
    return value;
  }
}

function segments(hash: string): string[] {
  const raw = hash.replace(/^#/, '').split('?')[0];
  const path = raw.startsWith('/') ? raw.slice(1) : raw;
  return path.split('/').filter(Boolean).map(decodeSegment);
}

export function parseHash(hash: string): Route {
  const parts = segments(hash);
  if (parts.length === 0) return { name: 'home' };

  const [head, ...rest] = parts;
  switch (head) {
    case 'archive':
      return rest.length === 0 ? { name: 'archive' } : { name: 'not-found', raw: parts.join('/') };
    case 'about':
      return rest.length === 0 ? { name: 'about' } : { name: 'not-found', raw: parts.join('/') };
    case 'tags':
      if (rest.length === 0) return { name: 'tags' };
      if (rest.length === 1) return { name: 'tag', tag: rest[0] };
      return { name: 'not-found', raw: parts.join('/') };
    case 'categories':
      if (rest.length === 0) return { name: 'categories' };
      return { name: 'category', category: rest.join('/') };
    case 'post':
      if (rest.length === 0) return { name: 'not-found', raw: parts.join('/') };
      return { name: 'post', id: rest.join('/') };
    default:
      return { name: 'not-found', raw: parts.join('/') };
  }
}

export const route: ComputedRef<Route> = computed(() => parseHash(currentHash.value));

/** 生成站内 hash 链接，逐段编码以兼容中文标签与多层路径。 */
export function linkTo(path: string): string {
  const encoded = path
    .split('/')
    .filter(Boolean)
    .map((part) => encodeURIComponent(part))
    .join('/');
  return `#/${encoded}`;
}

export function postLink(id: string): string {
  return linkTo(`/post/${id}`);
}

export function tagLink(tag: string): string {
  return linkTo(`/tags/${tag}`);
}

export function categoryLink(category: string): string {
  return linkTo(`/categories/${category}`);
}
