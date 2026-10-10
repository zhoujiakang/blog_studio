<script setup lang="ts">
import { computed } from 'vue';

import PostCard from '../components/PostCard.vue';
import { posts } from '../lib/content';
import { postsInCategory, postsWithTag } from '../lib/content-utils';

const props = defineProps<{ kind: 'tag' | 'category'; name: string }>();

const matched = computed(() =>
  props.kind === 'tag' ? postsWithTag(posts, props.name) : postsInCategory(posts, props.name),
);

const label = computed(() => (props.kind === 'tag' ? `标签 · ${props.name}` : `分类 · ${props.name}`));
</script>

<template>
  <div class="shell">
    <div class="section-heading">
      <h1 class="section-heading__title">{{ label }}</h1>
      <span class="section-heading__count">{{ matched.length }} 篇</span>
    </div>

    <div v-if="matched.length" class="grid">
      <PostCard v-for="post in matched" :key="post.id" :post="post" />
    </div>
    <div v-else class="empty">这个{{ kind === 'tag' ? '标签' : '分类' }}下没有公开文章。</div>
  </div>
</template>
