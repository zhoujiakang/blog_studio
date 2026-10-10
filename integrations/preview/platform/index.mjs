// The business installer consumes this contract. Add Windows selection here later.
import { installerPlatform as macos } from './macos.mjs';
if (process.platform !== 'darwin') throw Error('当前预览安装仅支持 macOS。');
export const installerPlatform = macos;
