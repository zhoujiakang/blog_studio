<script setup lang="ts">
import { computed } from 'vue';

import { about, site } from '../lib/content';
import { renderMarkdown } from '../lib/markdown';

const rendered = computed(() => renderMarkdown(about));
</script>

<template>
  <div class="reading">
    <div class="section-heading">
      <h1 class="section-heading__title">关于</h1>
      <span v-if="site.author" class="section-heading__count">{{ site.author }}</span>
    </div>

    <div v-if="about.trim()" class="markdown" v-html="rendered.html" />
    <div v-else class="empty">
      还没有填写关于内容。
      <p class="empty__hint">在拾笺里编辑「关于」页面，写点自我介绍。</p>
    </div>
  </div>
</template>
