<script setup lang="ts">
import { computed } from 'vue';

import { posts, site } from '../lib/content';
import { countWords, renderMarkdown } from '../lib/markdown';
import { formatDate, formatLongDate } from '../lib/content-utils';
import { categoryLink, postLink, tagLink } from '../lib/router';

const props = defineProps<{ id: string }>();

const post = computed(() => posts.find((item) => item.id === props.id) ?? null);

const rendered = computed(() => (post.value ? renderMarkdown(post.value.body) : { html: '', headings: [] }));

const index = computed(() => posts.findIndex((item) => item.id === props.id));

// posts 按时间倒序：index - 1 是较新的一篇，index + 1 是较早的一篇。
const newer = computed(() => (index.value > 0 ? posts[index.value - 1] : null));
const older = computed(() => (index.value >= 0 && index.value < posts.length - 1 ? posts[index.value + 1] : null));

const wordCount = computed(() => (post.value ? countWords(post.value.body) : 0));

const updatedLabel = computed(() => {
  if (!post.value) return '';
  if (post.value.updated === post.value.date) return '';
  const revised = formatLongDate(post.value.updated);
  return revised === '' ? '' : `更新于 ${revised}`;
});
</script>

<template>
  <div v-if="post" class="reading">
    <header class="post-head">
      <h1 class="post-head__title">{{ post.title }}</h1>
      <div class="post-head__meta">
        <span v-if="formatDate(post.date)">{{ formatDate(post.date) }}</span>
        <span v-if="updatedLabel">{{ updatedLabel }}</span>
        <span v-if="site.author">{{ site.author }}</span>
        <span v-if="wordCount">{{ wordCount }} 字</span>
        <a v-for="category in post.categories" :key="`c-${category}`" :href="categoryLink(category)">
          {{ category }}
        </a>
      </div>
      <p v-if="post.summary" class="post-head__summary">{{ post.summary }}</p>
    </header>

    <nav v-if="rendered.headings.length > 2" class="post-toc" aria-label="目录">
      <p class="post-toc__label">目录</p>
      <ol class="post-toc__list">
        <li
          v-for="(heading, position) in rendered.headings"
          :key="`${heading.id}-${position}`"
          :class="`post-toc__item post-toc__item--d${Math.min(heading.depth, 4)}`"
        >
          <a :href="`#${heading.id}`">{{ heading.text }}</a>
        </li>
      </ol>
    </nav>

    <div class="markdown post-body" v-html="rendered.html" />

    <footer class="post-foot">
      <a v-for="tag in post.tags" :key="`tag-${tag}`" :href="tagLink(tag)">#{{ tag }}</a>
    </footer>

    <nav class="post-nav">
      <a v-if="newer" class="post-nav__item" :href="postLink(newer.id)">← 较新：{{ newer.title }}</a>
      <span v-else />
      <a
        v-if="older"
        class="post-nav__item post-nav__item--next"
        :href="postLink(older.id)"
      >
        较早：{{ older.title }} →
      </a>
    </nav>
  </div>
  <div v-else class="reading empty">没有找到这篇文章。</div>
</template>

<style scoped>
.post-toc {
  border: 1px solid var(--rule-soft);
  background: var(--surface);
  padding: 1.1rem 1.3rem;
  margin-bottom: 2.6rem;
}

.post-toc__label {
  margin: 0 0 0.6rem;
  font-size: 0.72rem;
  letter-spacing: 0.2em;
  color: var(--ink-faint);
}

.post-toc__list {
  margin: 0;
  padding-left: 1.1rem;
  font-size: 0.88rem;
}

.post-toc__item {
  margin-bottom: 0.25rem;
}

.post-toc__item--d3 {
  margin-left: 1rem;
}

.post-toc__item--d4 {
  margin-left: 2rem;
}

.post-toc__item a:hover {
  color: var(--accent);
}
</style>
