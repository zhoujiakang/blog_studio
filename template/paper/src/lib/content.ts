import content from 'virtual:blog-content';

import { readTheme } from './theme';
import type { BlogContent, Theme } from './types';

export const blog: BlogContent = content;

export const theme: Theme = readTheme(blog.theme);

export const site = blog.site;

export const posts = blog.posts;

export const about = blog.about;
