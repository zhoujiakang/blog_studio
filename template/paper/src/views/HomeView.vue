<script setup lang="ts">
import { computed } from 'vue';

import PostCard from '../components/PostCard.vue';
import SafeImage from '../components/SafeImage.vue';
import { posts, site, theme } from '../lib/content';

const countLabel = computed(() => {
  const total = posts.length;
  return total === 0 ? '还没有文章' : `共 ${total} 篇文章`;
});
</script>

<template>
  <div class="shell">
    <section class="hero">
      <SafeImage v-if="site.avatar" :src="site.avatar" :alt="site.title" block-class="hero__avatar" />
      <div>
        <h1 class="hero__title">{{ site.title || '我的博客' }}</h1>
        <p v-if="site.subtitle" class="hero__subtitle">{{ site.subtitle }}</p>
        <p v-if="site.description" class="hero__subtitle">{{ site.description }}</p>
        <p class="hero__meta">{{ countLabel }}</p>
      </div>
    </section>

    <p v-if="theme.announcement" class="announcement">{{ theme.announcement }}</p>

    <div v-if="posts.length" class="grid">
      <PostCard v-for="post in posts" :key="post.id" :post="post" />
    </div>
    <div v-else class="empty">
      这里还没有文章。
      <p class="empty__hint">在拾笺里写一篇并发布后，题目会出现在这个位置。</p>
    </div>
  </div>
</template>
