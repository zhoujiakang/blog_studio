/// <reference types="vite/client" />

declare module 'virtual:blog-content' {
  import type { BlogContent } from './lib/types';
  const content: BlogContent;
  export default content;
}

declare module '*.svg' {
  const source: string;
  export default source;
}

declare module '*.png' {
  const source: string;
  export default source;
}
