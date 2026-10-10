import { readFileSync, writeFileSync, existsSync } from 'node:fs';
import { join } from 'node:path';
const lock = JSON.parse(readFileSync('package-lock.json', 'utf8'));
const notices = [
  'InkJian editor bundled dependency notices\nGenerated from the locked dependency tree. Includes installed production dependencies.\n',
];
for (const [location, entry] of Object.entries(lock.packages)) {
  if (!location || entry.dev) continue;
  const metaPath = join(location, 'package.json');
  if (!existsSync(metaPath)) continue;
  const meta = JSON.parse(readFileSync(metaPath, 'utf8'));
  notices.push(
    `\n===== ${meta.name} ${meta.version} (${meta.license ?? 'see package license'}) =====\n`
  );
  const license = [
    'LICENSE',
    'LICENSE.md',
    'LICENSE.txt',
    'license',
    'license.md',
    'license.txt',
    'LICENSE-MIT',
  ].find((name) => existsSync(join(location, name)));
  notices.push(
    license
      ? readFileSync(join(location, license), 'utf8')
      : `License source: ${meta.repository?.url ?? meta.repository ?? meta.homepage ?? meta.name}\n`
  );
}
writeFileSync('../../assets/editor/THIRD_PARTY_NOTICES.txt', notices.join('\n'));
