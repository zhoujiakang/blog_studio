export interface Post {
  id: string;
  title: string;
  body: string;
  date: string;
  updated: string;
  tags: string[];
  categories: string[];
  summary: string;
  cover: string;
}
export interface Site {
  title: string;
  subtitle: string;
  description: string;
  author: string;
  avatar: string;

}
export interface BlogContent {
  theme: Record<string, string>;
  site: Site;
  posts: Post[];
  about: string;
}
