import { afterEach, beforeEach, expect, test, vi } from 'vitest';
import { mount, type VueWrapper } from '@vue/test-utils';
import App from '../src/App.vue';
import { renderMarkdown } from '../src/lib/markdown';
let wrapper: VueWrapper;
beforeEach(() => {
  history.replaceState(null, '', '/#/');
  localStorage.clear();
  vi.spyOn(window, 'scrollTo').mockImplementation(() => {});
  vi.stubGlobal('matchMedia', () => ({ matches: true }));
});
afterEach(() => {
  wrapper?.unmount();
  document.body.innerHTML = '';
  vi.restoreAllMocks();
});
function open(route: string) {
  history.replaceState(null, '', `/#${route}`);
  wrapper = mount(App, { attachTo: document.body });
  return wrapper;
}
test('home renders Butterfly structure and only published Markdown posts', () => {
  open('/');
  expect(wrapper.find('.home-hero').exists()).toBe(true);
  expect(wrapper.findAll('.post-card')).toHaveLength(4);
  expect(wrapper.find('.profile').text()).toContain('拾笺');
  expect(wrapper.text()).not.toContain('PRIVATE_DRAFT');
  expect(wrapper.find('.post-card').text()).toContain('Vue 博客');
});
test('article deep link renders code, table, TOC and previous/next links', () => {
  open('/post/vue-blog-guide');
  expect(wrapper.find('.prose table').exists()).toBe(true);
  expect(wrapper.find('.prose pre').exists()).toBe(true);
  expect(wrapper.findAll('.toc button').length).toBeGreaterThan(2);
  expect(wrapper.find('.post-navigation a').attributes('href')).toContain(
    'little-moments'
  );
  expect(document.title).toContain('Vue 博客');
});
test('Chinese tag and category routes filter their real articles', () => {
  open(`/tags/${encodeURIComponent('生活')}`);
  expect(wrapper.findAll('.timeline-post')).toHaveLength(1);
  expect(wrapper.find('.timeline-post').text()).toContain('留一点空白');
  wrapper.unmount();
  open(`/categories/${encodeURIComponent('技术笔记')}`);
  expect(wrapper.findAll('.timeline-post')).toHaveLength(2);
  expect(wrapper.find('.timeline-post').text()).toContain('Vue 博客');
});
test('archive and about use Markdown content', () => {
  open('/archives');
  expect(wrapper.findAll('.timeline-post')).toHaveLength(4);
  wrapper.unmount();
  open('/about');
  expect(wrapper.find('.prose').text()).toContain('关于拾笺');
});
test('search filters body and closes on Escape', async () => {
  open('/');
  await wrapper
    .findAll('.nav-links button')
    .find((b) => b.text() === '搜索')!
    .trigger('click');
  const input = document.querySelector<HTMLInputElement>('[aria-label="搜索关键词"]')!;
  expect(input).not.toBeNull();
  input.value = '构建完成';
  input.dispatchEvent(new Event('input', { bubbles: true }));
  await wrapper.vm.$nextTick();
  expect(document.querySelectorAll('.search-results a')).toHaveLength(1);
  expect(document.querySelector('.search-results')!.textContent).toContain('Vue 博客');
  window.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape' }));
  await wrapper.vm.$nextTick();
  expect(document.querySelector('[role="dialog"]')).toBeNull();
});
test('theme switch persists and mobile navigation can open', async () => {
  open('/');
  await wrapper.find('[aria-label="切换亮色模式"]').trigger('click');
  expect(wrapper.find('.blog').classes()).toContain('light');
  expect(localStorage.getItem('vue-blog-theme')).toBe('light');
  await wrapper.find('[aria-label="展开导航"]').trigger('click');
  expect(wrapper.find('.nav-links').classes()).toContain('open');
});
test('missing route and missing post show recovery link', () => {
  open('/post/no-such-post');
  expect(wrapper.find('.error-code').text()).toBe('404');
  expect(wrapper.find('.empty a').attributes('href')).toBe('#/');
});
test('Markdown blocks remain while executable HTML is removed', () => {
  const rendered = renderMarkdown(
    '## 标题\n\n<img src="x" onerror="alert(1)"><script>alert(1)</script>\n\n[bad](javascript:alert(1))\n\n---'
  );
  expect(rendered.html).not.toMatch(/onerror|<script|javascript:/);
  expect(rendered.html).toContain('<hr>');
  expect(rendered.headings).toEqual([{ id: 'section-0', text: '标题', level: 2 }]);
});
