import { spawn } from 'node:child_process';

export const installerPlatform = {
  spawn(executable, args, cwd) {
    return spawn(executable, args, {
      cwd,
      detached: true,
      env: process.env,
      stdio: ['ignore', 'pipe', 'pipe'],
    });
  },
  cancel(child) {
    const group = child?.pid;
    if (!group) return Promise.resolve();
    try {
      process.kill(-group, 'SIGTERM');
    } catch {}
    return new Promise((resolve) =>
      setTimeout(() => {
        try {
          process.kill(-group, 'SIGKILL');
        } catch {}
        resolve();
      }, 3000)
    );
  },
};
