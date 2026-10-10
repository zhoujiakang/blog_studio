import type { Theme } from './types';

const COLOR_PATTERN = /^#[0-9a-fA-F]{6}$/;

const FALLBACKS: Theme = {
  backgroundTint: '#FAF9F7',
  accentColor: '#1A1A1A',
  backgroundImage: '',
  announcement: '',
  footerText: '',
};

/** 主题字段取值已在 Node 端按 value ?? default 处理，这里只做类型与格式兜底。 */
export function readTheme(rawTheme: Record<string, string> | undefined): Theme {
  const source = rawTheme ?? {};
  return {
    backgroundTint: normalizeColor(source.backgroundTint, FALLBACKS.backgroundTint),
    accentColor: normalizeColor(source.accentColor, FALLBACKS.accentColor),
    backgroundImage: normalizeImage(source.backgroundImage),
    announcement: normalizeText(source.announcement),
    footerText: normalizeText(source.footerText),
  };
}

export function normalizeColor(value: unknown, fallback: string): string {
  if (typeof value !== 'string') return fallback;
  const text = value.trim();
  return COLOR_PATTERN.test(text) ? text : fallback;
}

export function normalizeImage(value: unknown): string {
  if (typeof value !== 'string') return '';
  return value.trim();
}

export function normalizeText(value: unknown): string {
  if (typeof value !== 'string') return '';
  return value.trim();
}

/**
 * 把共享图片路径写成适合 GitHub Pages 子路径的相对形式。
 * 内容里写作 /img/a.png，输出目录里位于同级 img/ 下，因此去掉前导斜杠即可。
 */
export function publicAssetUrl(value: unknown): string {
  const text = normalizeImage(value);
  if (text === '' || text.startsWith('#')) return '';
  if (/^(https?:|data:|\/\/)/i.test(text)) return text;
  return text.replace(/^\/+/, '');
}

/** 把主题写入 CSS 变量，页面样式只读变量。 */
export function applyTheme(theme: Theme, backgroundImageUrl: string): void {
  if (typeof document === 'undefined') return;
  const root = document.documentElement;
  root.style.setProperty('--paper', theme.backgroundTint);
  root.style.setProperty('--accent', theme.accentColor);
  root.style.setProperty('--paper-image', backgroundImageUrl ? `url("${escapeUrl(backgroundImageUrl)}")` : 'none');
}

function escapeUrl(value: string): string {
  return value.replace(/["'\\]/g, '\\$&');
}
