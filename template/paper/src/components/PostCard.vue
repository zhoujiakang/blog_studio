<script setup lang="ts">
import { computed } from 'vue';

import SafeImage from './SafeImage.vue';
import { categoryLink, postLink, tagLink } from '../lib/router';
import { formatDate } from '../lib/content-utils';
import type { Post } from '../lib/types';

const props = defineProps<{ post: Post }>();

const dateLabel = computed(() => formatDate(props.post.date));
</script>

<template>
  <article class="card">
    <SafeImage
      v-if="post.cover"
      :src="post.cover"
      :alt="post.title"
      block-class="card__cover"
    />
    <span v-if="dateLabel" class="card__date">{{ dateLabel }}</span>
    <h2 class="card__title">
      <a :href="postLink(post.id)">{{ post.title }}</a>
    </h2>
    <p v-if="post.summary" class="card__summary">{{ post.summary }}</p>
    <div v-if="post.tags.length || post.categories.length" class="card__tags">
      <a
        v-for="tag in post.tags"
        :key="`tag-${tag}`"
        class="tag-chip"
        :href="tagLink(tag)"
      >
        #{{ tag }}
      </a>
      <a
        v-for="category in post.categories"
        :key="`category-${category}`"
        class="tag-chip"
        :href="categoryLink(category)"
      >
        {{ category }}
      </a>
    </div>
  </article>
</template>
