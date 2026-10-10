import { marked } from 'marked';
import DOMPurify from 'dompurify';
export function renderMarkdown(source: string) {
  const clean = DOMPurify.sanitize(marked.parse(source, { async: false, breaks: true }), {
    USE_PROFILES: { html: true },
    FORBID_TAGS: ['style', 'iframe'],
    FORBID_ATTR: ['style'],
  });
  const document = new DOMParser().parseFromString(clean, 'text/html');
  const headings = [...document.querySelectorAll('h1,h2,h3,h4')].map((heading, index) => {
    heading.id = `section-${index}`;
    return {
      id: heading.id,
      text: heading.textContent || '',
      level: Number(heading.tagName.slice(1)),
    };
  });
  document.querySelectorAll('img').forEach((image) => {
    const src = image.getAttribute('src') || '';
    if (src.startsWith('/') && !src.startsWith('//'))
      image.setAttribute('src', `${import.meta.env.BASE_URL}${src.slice(1)}`);
  });
  document.querySelectorAll('a').forEach((a) => {
    if (/^https?:/.test(a.href)) {
      a.target = '_blank';
      a.rel = 'noopener noreferrer';
    }
  });
  return { html: document.body.innerHTML, headings };
}
