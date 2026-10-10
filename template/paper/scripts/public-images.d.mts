import type { BlogBundle } from './content.d.mts';

export function collectPublicImages(bundle: BlogBundle): Promise<Map<string, string>>;
export function matchWhitelistedImage(whitelist: Map<string, string>, urlPath: string): string | null;
