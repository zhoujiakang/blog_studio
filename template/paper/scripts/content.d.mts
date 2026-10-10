export interface PostFrontBody {
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

export interface BlogSite {
  title: string;
  subtitle: string;
  author: string;
  description: string;
  avatar: string;
}

export interface BlogLocation {
  blogRoot: string;
  blogJsonPath: string;
  templateDirectory: string;
  activeTemplate: string;
  site: BlogSite;
}

export interface BlogRawContent {
  site: BlogSite;
  posts: PostFrontBody[];
  about: string;
  theme: Record<string, string>;
}

export interface BlogBundle {
  location: BlogLocation;
  content: BlogRawContent;
}

export function locateBlog(templateDirectory: string): BlogLocation;
export function loadContent(templateDirectory: string): BlogBundle;
export function loadThemeFields(templateSourceDirectory: string): Record<string, string>;
export function parsePost(markdown: string, relativeFilename: string): PostFrontBody | null;

export const EPOCH_ISO: string;
