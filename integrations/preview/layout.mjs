import fs from 'node:fs/promises';
import path from 'node:path';

export async function resolveBlog(rootArg) {
  const root = await fs.realpath(rootArg);
  const file = path.join(root, 'blog.json');
  if ((await fs.lstat(file)).isSymbolicLink()) throw Error('博客清单不能是符号链接');
  const marker = JSON.parse(await fs.readFile(file, 'utf8'));
  if (
    !marker || marker.formatVersion !== 2 || typeof marker.activeTemplate !== 'string' ||
    !/^[a-zA-Z0-9\u4e00-\u9fff][a-zA-Z0-9_\u4e00-\u9fff-]*$/.test(marker.activeTemplate)
  )
    throw Error('博客资源格式不支持');
  if (!(await fs.stat(path.join(root, 'resource'))).isDirectory())
    throw Error('缺少 resource 目录');
  const template = `template/${marker.activeTemplate}/`;
  for (const directory of [path.join(root, 'template'), path.join(root, template)]) {
    if ((await fs.lstat(directory)).isSymbolicLink())
      throw Error('模板不能是符号链接');
  }
  return {
    root,
    packageRoot: path.join(root, template),
    template,
    resource: 'resource',
    marker,
  };
}
