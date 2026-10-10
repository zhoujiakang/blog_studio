import fs from 'node:fs/promises';
import net from 'node:net';
import { pathToFileURL } from 'node:url';
import readline from 'node:readline';
import { resolveBlog } from './layout.mjs';
import { inspectDependencies } from './probe.mjs';
import { installerPlatform } from './platform/index.mjs';

async function availablePort() {
  const socket = net.createServer();
  await new Promise((resolve, reject) => {
    socket.once('error', reject);
    socket.listen(0, '127.0.0.1', resolve);
  });
  const port = socket.address().port;
  await new Promise((resolve, reject) => socket.close((e) => e ? reject(e) : resolve()));
  return port;
}

// The template owns its server, content parsing, watchers and rendering.
export async function startPreview(rootArg, {
  npmPath = 'npm', onLog = () => {}, onExit = () => {}, signal,
  startupTimeout = 20000,
} = {}) {
  const { packageRoot } = await resolveBlog(rootArg);
  const health = await inspectDependencies(rootArg, npmPath);
  if (health.status !== 'ready') throw Error(health.reason ?? '博客依赖不可用');
  if (signal?.aborted) throw Error('预览已取消');
  const port = await availablePort();
  const url = `http://127.0.0.1:${port}/`;
  const child = installerPlatform.spawn(npmPath, [
    'run', 'dev', '--', '--host', '127.0.0.1', '--port', String(port), '--strictPort',
  ], packageRoot);
  let failure, stopped = false, ready = false, stopping;
  for (const stream of [child.stdout, child.stderr])
    stream.on('data', (bytes) => onLog(bytes.toString().slice(0, 8000)));
  child.once('error', (e) => { failure = e; });
  child.once('exit', (code, signal) => {
    failure = Error(`模板预览进程已停止（${code ?? signal}），请检查模板 dev 脚本和日志。`);
    if (ready && !stopped) onExit(failure);
  });
  function stop() {
    if (stopping) return stopping;
    stopped = true;
    return stopping = installerPlatform.cancel(child);
  }
  const abort = () => { void stop(); };
  signal?.addEventListener('abort', abort, { once: true });
  try {
    const deadline = Date.now() + startupTimeout;
    while (true) {
      if (signal?.aborted || stopped) throw Error('预览已取消');
      if (failure) throw failure;
      try {
        const response = await fetch(url, { signal: AbortSignal.timeout(1000), redirect: 'error' });
        await response.body?.cancel();
        if (response.ok) break;
      } catch { /* Wait for the template's HTTP server. */ }
      if (Date.now() >= deadline) throw Error('模板预览启动超时，请检查 dev 脚本是否支持本机地址和指定端口。');
      await new Promise((resolve) => setTimeout(resolve, 100));
    }
    if (failure) throw failure;
    ready = true;
    return {
      url,
      async refresh() {
        if (failure || stopped) throw failure ?? Error('预览已停止');
        // Content changes and browser reloads are handled by the template watcher.
      },
      async stop() {
        signal?.removeEventListener('abort', abort);
        await stop();
      },
    };
  } catch (e) {
    signal?.removeEventListener('abort', abort);
    await stop();
    throw e;
  }
}
if (
  process.argv[1] &&
  import.meta.url === pathToFileURL(await fs.realpath(process.argv[1])).href
) {
  let preview;
  const abort = new AbortController();
  const send = (event) => process.stdout.write(JSON.stringify(event) + '\n');
  const lines = readline.createInterface({ input: process.stdin });
  let queue = Promise.resolve();
  lines.on('line', (line) => {
    try { if (JSON.parse(line).type === 'stop') abort.abort(); } catch {}
    queue = queue
      .then(async () => {
        const command = JSON.parse(line);
        if (command.type === 'start') {
          preview = await startPreview(process.argv[2], {
            npmPath: process.argv[3], signal: abort.signal,
            onLog: (text) => send({ type: 'log', text }),
            onExit: (e) => {
              send({ type: 'error', message: e.message });
              lines.close();
              process.stdin.destroy();
            },
          });
          send({ type: 'ready', url: preview.url, request: command.request });
        }
        if (command.type === 'refresh') {
          await preview.refresh();
          send({ type: 'updated', request: command.request });
        }
        if (command.type === 'stop') {
          await preview?.stop();
          preview = null;
          send({ type: 'stopped', request: command.request });
          lines.close();
          process.stdin.destroy();
        }
      })
      .catch((e) => send({ type: 'error', message: e.message }));
  });
  process.on('SIGTERM', () => { abort.abort(); lines.close(); process.stdin.destroy(); });
  lines.on('close', () => {
    abort.abort();
    queue = queue.then(async () => {
      if (preview) {
        await preview.stop();
        preview = null;
      }
    });
  });
}
