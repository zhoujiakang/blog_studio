import hljs from 'highlight.js/lib/core';
import bash from 'highlight.js/lib/languages/bash';
import css from 'highlight.js/lib/languages/css';
import go from 'highlight.js/lib/languages/go';
import java from 'highlight.js/lib/languages/java';
import javascript from 'highlight.js/lib/languages/javascript';
import json from 'highlight.js/lib/languages/json';
import kotlin from 'highlight.js/lib/languages/kotlin';
import markdown from 'highlight.js/lib/languages/markdown';
import python from 'highlight.js/lib/languages/python';
import rust from 'highlight.js/lib/languages/rust';
import sql from 'highlight.js/lib/languages/sql';
import typescript from 'highlight.js/lib/languages/typescript';
import xml from 'highlight.js/lib/languages/xml';
import yaml from 'highlight.js/lib/languages/yaml';

// Explicit languages keep the website small and avoid guessing prose as code.
for (const [name, grammar] of Object.entries({
  bash, css, go, java, javascript, json, kotlin, markdown, python, rust, sql, typescript, xml, yaml,
})) hljs.registerLanguage(name, grammar);

export function decorateCodeBlocks(document: Document) {
  document.querySelectorAll('pre > code').forEach((code) => {
    const pre = code.parentElement!;
    const source = code.textContent || '';
    const language = [...code.classList]
      .find((name) => name.startsWith('language-'))?.slice(9).toLowerCase() || '';
    const grammar = hljs.getLanguage(language);
    if (grammar && source.length < 100000) {
      code.innerHTML = hljs.highlight(source, { language, ignoreIllegals: true }).value;
    }
    code.classList.add('hljs');
    const block = document.createElement('figure');
    block.className = 'code-block';
    const toolbar = document.createElement('div');
    toolbar.className = 'code-toolbar';
    const label = document.createElement('span');
    label.className = 'code-language';
    label.textContent = grammar?.name || language.slice(0, 40) || '纯文本';
    const copy = document.createElement('button');
    copy.type = 'button';
    copy.className = 'code-copy';
    copy.setAttribute('data-copy-code', '');
    copy.setAttribute('aria-label', '复制代码');
    copy.setAttribute('aria-live', 'polite');
    copy.textContent = '复制';
    toolbar.append(label, copy);
    pre.replaceWith(block);
    block.append(toolbar, pre);
  });
}

export async function copyCode(event: MouseEvent) {
  if (!(event.target instanceof Element)) return;
  const button = event.target.closest<HTMLButtonElement>('[data-copy-code]');
  const code = button?.closest('.code-block')?.querySelector('pre > code');
  if (!button || !code || button.disabled) return;
  button.disabled = true;
  try {
    await navigator.clipboard.writeText(code.textContent || '');
    button.textContent = '已复制';
  } catch {
    button.textContent = '复制失败，请选择代码';
  } finally {
    button.disabled = false;
  }
}
