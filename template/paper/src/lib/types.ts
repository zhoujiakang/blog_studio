/** 虚拟模块 virtual:blog-content 的公开数据形状，与 DEVELOPMENT.md 6.3 一致。 */

export interface Post {
  id: string;
  title: string;
  body: string;
  date: string;
  updated: string;
  tags: string[];
  categories: string[];
  /** 仅来自 Front Matter description；为空表示不显示摘要。 */
  summary: string;
  cover: string;
}

export interface Site {
  title: string;
  subtitle: string;
  author: string;
  description: string;
  avatar: string;
}

export interface BlogContent {
  site: Site;
  posts: Post[];
  about: string;
  theme: Record<string, string>;
}

export interface Theme {
  backgroundTint: string;
  accentColor: string;
  backgroundImage: string;
  announcement: string;
  footerText: string;
}

export interface Heading {
  depth: number;
  id: string;
  text: string;
}
