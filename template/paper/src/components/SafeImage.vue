<script setup lang="ts">
import { ref, watch } from 'vue';

import { publicAssetUrl } from '../lib/theme';

const props = defineProps<{
  src: string;
  alt?: string;
  blockClass?: string;
}>();

/** 图片缺失时不显示破损占位：加载失败后直接移除元素。 */
const failed = ref(false);
watch(
  () => props.src,
  () => {
    failed.value = false;
  },
);

const source = () => publicAssetUrl(props.src);
</script>

<template>
  <img
    v-if="source() && !failed"
    :src="source()"
    :alt="alt ?? ''"
    :class="blockClass"
    loading="lazy"
    decoding="async"
    @error="failed = true"
  />
</template>
