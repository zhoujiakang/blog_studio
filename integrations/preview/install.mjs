import fs from 'node:fs/promises';
import { resolveBlog } from './layout.mjs';
import path from 'node:path';
import { installerPlatform } from './platform/index.mjs';
import { packageManifestIdentity, inspectPackageDependencies } from './probe.mjs';

const [rootArg, npmPath, identityArg] = process.argv.slice(2);
const root = (await resolveBlog(rootArg)).packageRoot;
const approved = JSON.parse(identityArg);
let child,
  stage,
  cancelled = false,
  committing = false,
  keepStage = false;
let cancellationFinished = Promise.resolve();
const send = (event) => process.stdout.write(JSON.stringify(event) + '\n');
function cancel() {
  if (committing) return;
  cancelled = true;
  cancellationFinished = installerPlatform.cancel(child);
}
process.stdin.on('data', cancel);
process.stdin.on('end', cancel);
process.on('SIGTERM', cancel);
try {
  const current = await packageManifestIdentity(root);
  if (JSON.stringify(current) !== JSON.stringify(approved))
    throw Error('依赖清单已变化，请重新确认安装');
  stage = await fs.mkdtemp(path.join(root, '.studio-install-'));
  await fs.copyFile(path.join(root, 'package.json'), path.join(stage, 'package.json'));
  if (current.lockHash)
    await fs.copyFile(
      path.join(root, 'package-lock.json'),
      path.join(stage, 'package-lock.json')
    );
  const args = [
    current.lockHash ? 'ci' : 'install',
    '--include=dev',
    '--ignore-scripts',
    '--no-audit',
    '--no-fund',
    ...(current.lockHash ? [] : ['--package-lock=false']),
  ];
  if (cancelled) throw Error('安装已取消');
  child = installerPlatform.spawn(npmPath, args, stage);
  for (const stream of [child.stdout, child.stderr])
    stream.on('data', (bytes) =>
      send({ type: 'log', text: bytes.toString().slice(0, 8000) })
    );
  const code = await new Promise((resolve, reject) => {
    child.on('error', reject);
    child.on('exit', resolve);
  });
  if (cancelled) await cancellationFinished;
  child = null;
  if (cancelled) throw Error('安装已取消');
  if (code !== 0) throw Error(`npm 安装失败（${code}），请查看日志`);
  const health = await inspectPackageDependencies(stage, npmPath);
  if (health.status !== 'ready') throw Error(health.reason ?? '安装后依赖检查未通过');
  if (JSON.stringify(await packageManifestIdentity(root)) !== JSON.stringify(approved))
    throw Error('安装期间依赖清单发生变化，未提交依赖');
  if (cancelled) throw Error('安装已取消');
  committing = true;
  const target = path.join(root, 'node_modules'),
    backup = path.join(stage, 'previous-node_modules');
  let hadOld = false;
  try {
    await fs.rename(target, backup);
    hadOld = true;
  } catch (e) {
    if (e.code !== 'ENOENT') throw e;
  }
  try {
    await fs.rename(path.join(stage, 'node_modules'), target);
  } catch (e) {
    if (hadOld) {
      try {
        await fs.rename(backup, target);
      } catch {
        keepStage = true;
        throw Error(`依赖提交与恢复失败，旧依赖保留在 ${backup}`);
      }
    }
    throw e;
  }
  send({ type: 'done' });
} catch (e) {
  send({ type: 'error', message: e.message });
  process.exitCode = 1;
} finally {
  if (stage && !keepStage) await fs.rm(stage, { recursive: true, force: true });
  process.stdin.destroy();
}
