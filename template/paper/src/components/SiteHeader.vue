<script setup lang="ts">
import { computed } from 'vue';

import { site } from '../lib/content';
import { linkTo, route } from '../lib/router';

interface NavItem {
  label: string;
  href: string;
  match: string[];
}

const items: NavItem[] = [
  { label: '首页', href: linkTo('/'), match: ['home'] },
  { label: '归档', href: linkTo('/archive'), match: ['archive'] },
  { label: '标签', href: linkTo('/tags'), match: ['tags', 'tag'] },
  { label: '分类', href: linkTo('/categories'), match: ['categories', 'category'] },
  { label: '关于', href: linkTo('/about'), match: ['about'] },
];

const currentName = computed(() => route.value.name);
</script>

<template>
  <header class="masthead">
    <div class="shell masthead__inner">
      <h1 class="masthead__title">
        <a :href="linkTo('/')">{{ site.title || '我的博客' }}</a>
        <span v-if="site.subtitle" class="masthead__subtitle">{{ site.subtitle }}</span>
      </h1>
      <nav class="nav" aria-label="站点导航">
        <a
          v-for="item in items"
          :key="item.href"
          class="nav__link"
          :href="item.href"
          :data-active="item.match.includes(currentName) ? 'true' : 'false'"
        >
          {{ item.label }}
        </a>
      </nav>
    </div>
  </header>
</template>
