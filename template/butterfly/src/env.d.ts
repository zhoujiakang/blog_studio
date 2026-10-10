/// <reference types="vite/client" />
declare module 'virtual:blog-content' {
  const content: import('./lib/types').BlogContent;
  export default content;
}
