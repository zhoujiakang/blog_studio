<script setup lang="ts">
withDefaults(defineProps<{ name: string; size?: number }>(), { size: 20 });
const paths: Record<string, string> = {
  home: 'M3 10 12 3l9 7M5 9v12h14V9M9 21v-8h6v8',
  tag: 'M3 3h8l10 10-8 8L3 11ZM7 7h.01',
  user: 'M12 3a4 4 0 1 1 0 8 4 4 0 0 1 0-8M4 21v-2a8 8 0 0 1 16 0v2',
  sun: 'M12 8a4 4 0 1 1 0 8 4 4 0 0 1 0-8M12 2v2m0 16v2M2 12h2m16 0h2M5 5l1 1m12 12 1 1M5 19l1-1M18 6l1-1',
  moon: 'M21 13A9 9 0 0 1 11 3a9 9 0 1 0 10 10Z',
  down: 'm6 9 6 6 6-6',
  up: 'm6 15 6-6 6 6',
  calendar: 'M4 5h16v16H4ZM8 3v4m8-4v4M4 10h16',
  megaphone: 'M3 9h5l12-5v16L8 15H3ZM7 15l2 6h4l-2-5',
  list: 'M8 6h13M8 12h13M8 18h13M3 6h.01M3 12h.01M3 18h.01',
  chart: 'M4 20V10m8 10V4m8 16v-7',
  plus: 'M12 5v14M5 12h14',
  arrow: 'M5 12h14m-5-5 5 5-5 5',
  back: 'M19 12H5m5-5-5 5 5 5',
  search: 'M21 21l-5-5M18 10a8 8 0 1 1-16 0 8 8 0 0 1 16 0',
  feather: 'M20 4c-4-4-12 2-12 8l4 4c6 0 12-8 8-12ZM4 20 17 7M8 12H5m7 4v3',
  book: 'M4 4h7l1 2 1-2h7v15h-7l-1 2-1-2H4ZM12 6v15',
  note: 'M5 3h14v18H5ZM8 8h8M8 12h8M8 16h5',
  archive: 'M3 3h18v4H3ZM5 7v14h14V7M9 12h6',
  settings:
    'M12 8a4 4 0 1 1 0 8 4 4 0 0 1 0-8M12 2v3m0 14v3M2 12h3m14 0h3M5 5l2 2m10 10 2 2M5 19l2-2M17 7l2-2',
  check: 'm5 12 4 4L19 6',
  trash: 'M3 6h18M9 6V3h6v3M5 6l1 15h12l1-15M10 10v7m4-7v7',
  eye: 'M2 12s4-7 10-7 10 7 10 7-4 7-10 7S2 12 2 12ZM12 9a3 3 0 1 1 0 6 3 3 0 0 1 0-6',
  download: 'M12 3v12m-5-5 5 5 5-5M4 15v6h16v-6',
  folder: 'M3 5h6l2 3h10v12H3Z',
  close: 'm6 6 12 12M6 18 18 6',
  mail: 'M3 5h18v14H3Zm0 0 9 7 9-7',
  clock: 'M12 3a9 9 0 1 1 0 18 9 9 0 0 1 0-18m0 4v5l3 2',
};
</script>
<template>
  <svg
    :width="size"
    :height="size"
    viewBox="0 0 24 24"
    fill="none"
    stroke="currentColor"
    stroke-width="1.6"
    stroke-linecap="round"
    stroke-linejoin="round"
    aria-hidden="true"
  >
    <path :d="paths[name] || paths.note" />
  </svg>
</template>
