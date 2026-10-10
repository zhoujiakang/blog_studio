<script setup lang="ts">
import { computed } from 'vue';

import { posts } from '../lib/content';
import { collectCategories, collectTags } from '../lib/content-utils';
import { categoryLink, tagLink } from '../lib/router';
import type { CategoryStat, TagStat } from '../lib/content-utils';

const props = defineProps<{ kind: 'tags' | 'categories' }>();

const title = computed(() => (props.kind === 'tags' ? '标签' : '分类'));

const tags = computed<TagStat[]>(() => (props.kind === 'tags' ? collectTags(posts) : []));

/** categories: ["技术/Flutter"] 是层级路径，因此按层级分组展示。 */
const categories = computed<CategoryStat[]>(() =>
  props.kind === 'categories' ? collectCategories(posts) : [],
);

const groups = computed(() => {
  const buckets = new Map<string, CategoryStat[]>();
  for (const category of categories.value) {
    const root = category.parts[0] ?? category.name;
    const bucket = buckets.get(root) ?? [];
    bucket.push(category);
    buckets.set(root, bucket);
  }
  return [...buckets.keys()].sort((a, b) => a.localeCompare(b, 'zh-CN'));
});

const itemsOf = (root: string) => categories.value.filter((item) => (item.parts[0] ?? item.name) === root);
</script>

<template>
  <div class="shell">
    <div class="section-heading">
      <h1 class="section-heading__title">{{ title }}</h1>
      <span class="section-heading__count">
        {{ kind === 'tags' ? tags.length : categories.length }} 项
      </span>
    </div>

    <div v-if="kind === 'tags'">
      <div v-if="tags.length" class="taxonomy">
        <a v-for="tag in tags" :key="tag.name" class="taxonomy__item" :href="tagLink(tag.name)">
          {{ tag.name }}<span class="taxonomy__count">{{ tag.count }}</span>
        </a>
      </div>
      <div v-else class="empty">还没有标签。给文章加上 tags 之后，这里会自动汇总。</div>
    </div>

    <div v-else>
      <section v-for="root in groups" :key="root" class="category-group">
        <h2 class="category-group__name">{{ root }}</h2>
        <div class="taxonomy">
          <a
            v-for="item in itemsOf(root)"
            :key="item.name"
            class="taxonomy__item"
            :href="categoryLink(item.name)"
          >
            {{ item.name }}<span class="taxonomy__count">{{ item.count }}</span>
          </a>
        </div>
      </section>
      <div v-if="!groups.length" class="empty">还没有分类。</div>
    </div>
  </div>
</template>
