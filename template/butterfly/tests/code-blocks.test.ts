import { expect, test, vi } from 'vitest';
import { renderMarkdown } from '../src/lib/markdown';
import { copyCode } from '../src/lib/code-blocks';

function render(source: string) {
  const document = new DOMParser().parseFromString(renderMarkdown(source).html, 'text/html');
  return document;
}

test('Java highlighting preserves whitespace and escapes HTML inside code', () => {
  const source = 'public class Demo {\n    String value = "<script>alert(1)</script>";\n}\n';
  const document = render('```java\n' + source + '```');
  expect(document.querySelector('.code-language')?.textContent).toBe('Java');
  expect(document.querySelector('pre code')?.textContent).toBe(source);
  expect(document.querySelector('.hljs-keyword')?.textContent).toBe('public');
  expect(document.querySelector('script')).toBeNull();
  expect(document.querySelectorAll('[data-copy-code]')).toHaveLength(1);
});

test('unknown languages and unlabelled blocks remain plain text', () => {
  const source = '  raw <value>\n';
  for (const language of ['', 'unsupported']) {
    const document = render('```' + language + '\n' + source + '```');
    expect(document.querySelector('pre code')?.textContent).toBe(source);
    expect(document.querySelector('.hljs-keyword')).toBeNull();
    expect(document.querySelector('.code-language')?.textContent).toBe(language || '纯文本');
  }
});

test('copy selects its own code block and reports clipboard failure', async () => {
  const document = render('```java\nint a = 1;\n```\n\n```json\n{"b": 2}\n```');
  const writeText = vi.fn().mockResolvedValue(undefined);
  vi.stubGlobal('navigator', { clipboard: { writeText } });
  try {
    const button = document.querySelectorAll<HTMLButtonElement>('[data-copy-code]')[1]!;
    const target = new MouseEvent('click');
    Object.defineProperty(target, 'target', { value: button });
    await copyCode(target);
    expect(writeText).toHaveBeenCalledWith('{"b": 2}\n');
    expect(button.textContent).toBe('已复制');
    expect(button.disabled).toBe(false);
    writeText.mockRejectedValueOnce(new Error('denied'));
    await copyCode(target);
    expect(button.textContent).toContain('复制失败');
    expect(button.disabled).toBe(false);
  } finally { vi.unstubAllGlobals(); }
});
