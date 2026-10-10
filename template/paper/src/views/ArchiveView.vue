<script setup lang="ts">
import { computed } from 'vue';

import { posts } from '../lib/content';
import { formatDate, yearOf } from '../lib/content-utils';
import { postLink } from '../lib/router';

interface YearGroup {
  year: string;
  items: Array<{ id: string; title: string; dateLabel: string }>;
}

const groups = computed<YearGroup[]>(() => {
  const buckets = new Map<string, YearGroup>();
  for (const post of posts) {
    const year = yearOf(post.date);
    const group = buckets.get(year) ?? { year, items: [] };
    group.items.push({ id: post.id, title: post.title, dateLabel: formatDate(post.date) });
    buckets.set(year, group);
  }
  return [...buckets.values()].sort((a, b) => b.year.localeCompare(a.year));
});
</script>

<template>
  <div class="shell">
    <div class="section-heading">
      <h1 class="section-heading__title">归档</h1>
      <span class="section-heading__count">{{ posts.length }} 篇</span>
    </div>

    <div v-if="groups.length">
      <section v-for="group in groups" :key="group.year" class="archive-year">
        <h2 class="archive-year__label">{{ group.year }}</h2>
        <a
          v-for="item in group.items"
          :key="item.id"
          class="archive-row"
          :href="postLink(item.id)"
        >
          <span class="archive-row__date">{{ item.dateLabel || '——' }}</span>
          <span class="archive-row__title">{{ item.title }}</span>
        </a>
      </section>
    </div>
    <div v-else class="empty">还没有可以归档的文章。</div>
  </div>
</template>
