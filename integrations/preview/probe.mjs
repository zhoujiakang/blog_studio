import fs from 'node:fs/promises';
import { resolveBlog } from './layout.mjs';
import path from 'node:path';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { pathToFileURL } from 'node:url';
import { createHash } from 'node:crypto';

export const digest = (buffer) => createHash('sha256').update(buffer).digest('hex');

export async function manifestIdentity(root) {
  return packageManifestIdentity((await resolveBlog(root)).packageRoot);
}

export async function packageManifestIdentity(root) {
  const manifest = await fs.readFile(path.join(root, 'package.json'));
  let lock;
  try {
    lock = await fs.readFile(path.join(root, 'package-lock.json'));
  } catch (error) {
    if (error.code !== 'ENOENT') throw error;
  }
  return { manifestHash: digest(manifest), lockHash: lock ? digest(lock) : null };
}

export async function inspectDependencies(root, npmPath = 'npm') {
  return inspectPackageDependencies((await resolveBlog(root)).packageRoot, npmPath);
}

// Installation staging is a package directory, not a user blog.
export async function inspectPackageDependencies(root, npmPath = 'npm') {
  const identity = await packageManifestIdentity(root);
  const manifest = JSON.parse(await fs.readFile(path.join(root, 'package.json'), 'utf8'));
  for (const script of ['dev', 'build']) {
    if (typeof manifest.scripts?.[script] !== 'string' || !manifest.scripts[script].trim())
      return { ...identity, status: 'manifestMismatch', missing: [], reason: `模板必须提供 npm run ${script}` };
  }
  // npm checks the template's declared dependencies and ranges; no framework
  // imports or executable module probes belong in the desktop application.
  let output, code = 0;
  try {
    ({ stdout: output } = await promisify(execFile)(npmPath,
      ['ls', '--json', '--depth=0', '--include=dev', '--ignore-scripts'],
      { cwd: root, timeout: 10000, maxBuffer: 2 * 1024 * 1024 }));
  } catch (e) {
    if (e.code !== 1 || !e.stdout) return {
      ...identity, status: 'broken', missing: [], reason: '无法检查模板依赖，请确认 npm 可运行。',
    };
    output = e.stdout;
    code = 1;
  }
  try {
    const result = JSON.parse(output);
    const missing = Object.entries(result.dependencies ?? {})
      .filter(([, value]) => value.missing).map(([name]) => name);
    if (missing.length) return { ...identity, status: 'missing', missing, reason: '模板依赖尚未完整安装' };
    if (code !== 0 || result.problems?.length) return {
      ...identity, status: 'manifestMismatch', missing: [], reason: '已安装依赖与模板清单不符，请重新安装。',
    };
    return { ...identity, status: 'ready', missing: [] };
  } catch {
    return { ...identity, status: 'broken', missing: [], reason: 'npm 返回的依赖数据无法识别。' };
  }
}

if (
  process.argv[1] &&
  import.meta.url === pathToFileURL(await fs.realpath(process.argv[1])).href
) {
  try {
    process.stdout.write(
      JSON.stringify(await inspectDependencies(process.argv[2], process.argv[3])) + '\n'
    );
  } catch (error) {
    process.stdout.write(
      JSON.stringify({ status: 'broken', reason: error.code ?? error.message }) + '\n'
    );
    process.exitCode = 1;
  }
}
