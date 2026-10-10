import DOMPurify from 'dompurify';
import { Marked } from 'marked';

import type { Heading } from './types';

const renderer = new Marked({ gfm: true, breaks: false });

export interface RenderedMarkdown {
  html: string;
  headings: Heading[];
}

/**
 * 渲染正文。使用 marked 解析后交给 DOMPurify 清理，
 * 绝不会把未清理的 HTML 直接交给 v-html。此函数在浏览器端运行。
 */
export function renderMarkdown(source: string): RenderedMarkdown {
  const markdown = typeof source === 'string' ? source : '';
  const parsed = renderer.parse(markdown, { async: false }) as unknown as string;
  const sanitized = DOMPurify.sanitize(parsed, {
    ADD_ATTR: ['target', 'rel'],
    FORBID_TAGS: ['iframe', 'object', 'embed', 'form', 'input', 'button', 'style'],
  });

  const document_ = new DOMParser().parseFromString(sanitized, 'text/html');
  const usedIds = new Map<string, number>();
  const headings: Heading[] = [];

  document_.querySelectorAll('h1, h2, h3, h4, h5, h6').forEach((element) => {
    const text = element.textContent?.trim() ?? '';
    const id = uniqueId(slugify(text), usedIds);
    element.setAttribute('id', id);
    headings.push({ depth: Number(element.tagName.slice(1)) || 2, id, text });
  });

  document_.querySelectorAll('img').forEach((image) => {
    const src = image.getAttribute('src') ?? '';
    if (src.startsWith('/img/')) {
      image.setAttribute('src', src.replace(/^\/+/, ''));
    }
    image.setAttribute('loading', 'lazy');
    if (image.getAttribute('alt') === null) image.setAttribute('alt', '');
  });

  document_.querySelectorAll('a').forEach((anchor) => {
    const href = anchor.getAttribute('href') ?? '';
    if (href.startsWith('/img/')) {
      anchor.setAttribute('href', href.replace(/^\/+/, ''));
    }
    if (/^https?:\/\//i.test(href)) {
      anchor.setAttribute('target', '_blank');
      anchor.setAttribute('rel', 'noopener noreferrer');
    }
  });

  document_.querySelectorAll('pre > code').forEach((code) => {
    code.parentElement?.setAttribute('data-code', 'true');
  });

  return { html: document_.body.innerHTML, headings };
}

export function slugify(text: string): string {
  const base = text
    .toLowerCase()
    .replace(/[\s]+/g, '-')
    .replace(/[^\p{L}\p{N}-]/gu, '')
    .replace(/-{2,}/g, '-')
    .replace(/^-|-$/g, '');
  return base === '' ? 'section' : base;
}

function uniqueId(base: string, usedIds: Map<string, number>): string {
  const count = usedIds.get(base) ?? 0;
  usedIds.set(base, count + 1);
  return count === 0 ? base : `${base}-${count}`;
}

/** 粗略估算中文与英文混合正文的字数，用于文章页元信息。 */
export function countWords(source: string): number {
  const text = source
    .replace(/```[\s\S]*?```/g, ' ')
    .replace(/[#>*`_\-[\]()!]/g, ' ');
  const chinese = text.match(/[\u4e00-\u9fa5]/g)?.length ?? 0;
  const words = text.match(/[A-Za-z0-9]+/g)?.length ?? 0;
  return chinese + words;
}
