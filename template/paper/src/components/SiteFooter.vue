<script setup lang="ts">
import { site, theme } from '../lib/content';

const year = new Date().getFullYear();
</script>

<template>
  <footer class="footer">
    <div class="shell footer__inner">
      <span>© {{ year }} {{ site.author || site.title || '我的博客' }}</span>
      <p v-if="theme.footerText" class="footer__note">{{ theme.footerText }}</p>
    </div>
  </footer>
</template>
