<script setup lang="ts">
import { computed, onMounted, watchEffect, type Component } from 'vue';

import grainTexture from './assets/paper-grain.svg';
import SiteFooter from './components/SiteFooter.vue';
import SiteHeader from './components/SiteHeader.vue';
import { posts, site, theme } from './lib/content';
import { route } from './lib/router';
import { applyTheme, publicAssetUrl } from './lib/theme';
import AboutView from './views/AboutView.vue';
import ArchiveView from './views/ArchiveView.vue';
import HomeView from './views/HomeView.vue';
import NotFoundView from './views/NotFoundView.vue';
import PostView from './views/PostView.vue';
import TaxonomyItemView from './views/TaxonomyItemView.vue';
import TaxonomyView from './views/TaxonomyView.vue';

interface ViewEntry {
  component: Component;
  props: Record<string, unknown>;
}

/** 用户没有配置背景图时使用模板自带的纸纹装饰。 */
const backgroundImage = computed(() => publicAssetUrl(theme.backgroundImage) || grainTexture);

watchEffect(() => {
  applyTheme(theme, backgroundImage.value);
});

const view = computed<ViewEntry>(() => {
  const current = route.value;
  switch (current.name) {
    case 'home':
      return { component: HomeView, props: {} };
    case 'archive':
      return { component: ArchiveView, props: {} };
    case 'about':
      return { component: AboutView, props: {} };
    case 'tags':
      return { component: TaxonomyView, props: { kind: 'tags' } };
    case 'categories':
      return { component: TaxonomyView, props: { kind: 'categories' } };
    case 'tag':
      return { component: TaxonomyItemView, props: { kind: 'tag', name: current.tag } };
    case 'category':
      return { component: TaxonomyItemView, props: { kind: 'category', name: current.category } };
    case 'post':
      return { component: PostView, props: { id: current.id } };
    default:
      return { component: NotFoundView, props: {} };
  }
});

watchEffect(() => {
  const suffix = site.title || '我的博客';
  const current = route.value;
  let prefix = '';
  if (current.name === 'archive') prefix = '归档 · ';
  else if (current.name === 'about') prefix = '关于 · ';
  else if (current.name === 'tags') prefix = '标签 · ';
  else if (current.name === 'categories') prefix = '分类 · ';
  else if (current.name === 'tag') prefix = `${current.tag} · `;
  else if (current.name === 'category') prefix = `${current.category} · `;
  else if (current.name === 'post') {
    prefix = `${posts.find((item) => item.id === current.id)?.title ?? '文章'} · `;
  }
  document.title = `${prefix}${suffix}`;
});

onMounted(() => {
  const description = document.querySelector('meta[name="description"]');
  if (description && site.description) {
    description.setAttribute('content', site.description);
  }
});
</script>

<template>
  <div class="app">
    <SiteHeader />
    <main>
      <component :is="view.component" v-bind="view.props" :key="JSON.stringify(view.props)" />
    </main>
    <SiteFooter />
  </div>
</template>
