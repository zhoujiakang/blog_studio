import { resolveBlog } from './layout.mjs';
import { installerPlatform } from './platform/index.mjs';
import fs from 'node:fs/promises';
import path from 'node:path';

const [rootArg, npmPath, outputArg] = process.argv.slice(2);
const { packageRoot } = await resolveBlog(rootArg);
const output = await fs.realpath(outputArg);
const send = (event) => process.stdout.write(JSON.stringify(event) + '\n');
let child, cancelled = false;
let cancellation = Promise.resolve();
function cancel() {
  if (cancelled) return;
  cancelled = true;
  cancellation = installerPlatform.cancel(child);
}
process.stdin.on('data', cancel);
process.stdin.on('end', cancel);
process.on('SIGTERM', cancel);
try {
  // Templates must accept Vite's --outDir override; build into an isolated directory.
  child = installerPlatform.spawn(npmPath, ['run', 'build', '--', '--outDir', output], packageRoot);
  for (const stream of [child.stdout, child.stderr])
    stream.on('data', (bytes) => send({ type: 'log', text: bytes.toString().slice(0, 8000) }));
  const code = await new Promise((resolve, reject) => {
    child.on('error', reject);
    child.on('exit', resolve);
  });
  if (cancelled) await cancellation;
  child = null;
  if (cancelled) throw Error('构建已取消');
  if (code !== 0) throw Error('博客构建失败，请先检查本地预览和模板');
  if (!(await fs.stat(path.join(output, 'index.html'))).isFile())
    throw Error('模板未生成网页入口，请检查模板构建配置');
  send({ type: 'done' });
} catch (e) {
  send({ type: 'error', message: e.message });
  process.exitCode = 1;
} finally {
  process.stdin.destroy();
}
