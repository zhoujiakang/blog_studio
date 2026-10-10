<script setup lang="ts">
import { linkTo } from '../lib/router';
</script>

<template>
  <div class="reading">
    <div class="section-heading">
      <h1 class="section-heading__title">没有找到</h1>
    </div>
    <div class="empty">
      这个地址不存在或已被移除。
      <p class="empty__hint"><a :href="linkTo('/')">← 回到首页</a></p>
    </div>
  </div>
</template>
