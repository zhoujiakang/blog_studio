import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import os from 'node:os';
import { startPreview } from './server.mjs';
import { inspectDependencies } from './probe.mjs';
const npmPath = path.join(path.dirname(process.execPath), 'npm');

async function fixture(script) {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), 'inkjian-custom-template-'));
  await fs.mkdir(path.join(root, 'resource'));
  const template = path.join(root, 'template/custom');
  await fs.mkdir(template, {recursive: true});
  await fs.writeFile(path.join(root, 'blog.json'), JSON.stringify({formatVersion: 2, activeTemplate: 'custom'}));
  await fs.writeFile(path.join(template, 'package.json'), JSON.stringify({
    name: 'custom-template', private: true, type: 'module', scripts: {dev: 'node dev.mjs', build: 'node dev.mjs'},
  }));
  await fs.writeFile(path.join(template, 'dev.mjs'), script);
  return {root, template};
}

test('runs a template without Vue/Vite and serves exactly the template response', async () => {
  const {root, template} = await fixture(`
    import http from 'node:http';
    import fs from 'node:fs';
    const args=process.argv;
    const host=args[args.indexOf('--host')+1], port=Number(args[args.indexOf('--port')+1]);
    if(host!=='127.0.0.1'||!args.includes('--strictPort'))throw Error('Invalid runner contract');
    http.createServer((req,res)=>res.end(fs.readFileSync('response.html'))).listen(port,host);
  `);
  let preview;
  try {
    await fs.writeFile(path.join(template, 'response.html'), 'CUSTOM_TEMPLATE_RESULT');
    assert.equal((await inspectDependencies(root, npmPath)).status, 'ready');
    preview = await startPreview(root, {npmPath});
    assert.equal(await (await fetch(preview.url)).text(), 'CUSTOM_TEMPLATE_RESULT');
    await fs.writeFile(path.join(template, 'response.html'), 'TEMPLATE_UPDATED_RESULT');
    await preview.refresh();
    assert.equal(await (await fetch(preview.url)).text(), 'TEMPLATE_UPDATED_RESULT');
    const url=preview.url;
    await preview.stop(); preview=null;
    await assert.rejects(fetch(url));
  } finally {await preview?.stop(); await fs.rm(root,{recursive:true,force:true});}
});

test('failed and cancelled template startups clean their process groups', async () => {
  const {root,template}=await fixture('process.exit(9)');
  try {
    await assert.rejects(startPreview(root,{npmPath}), /进程已停止/);
    await fs.writeFile(path.join(template,'dev.mjs'), 'setInterval(()=>{},1000)');
    await assert.rejects(startPreview(root,{npmPath,startupTimeout:300}), /启动超时/);
    const abort=new AbortController();
    const startup=startPreview(root,{npmPath,signal:abort.signal});
    const timer=setTimeout(()=>abort.abort(),500);
    try {await assert.rejects(startup,/取消/);} finally {clearTimeout(timer);}
  } finally {await fs.rm(root,{recursive:true,force:true});}
});

test('checks declared dependencies and script contract without importing template libraries', async () => {
  const {root,template}=await fixture('process.exit(0)');
  try {
    const manifest={name:'custom-template',private:true,scripts:{dev:'node dev.mjs',build:'node dev.mjs'},dependencies:{'custom-library':'1.0.0'}};
    await fs.writeFile(path.join(template,'package.json'),JSON.stringify(manifest));
    assert.equal((await inspectDependencies(root,npmPath)).status,'missing');
    const library=path.join(template,'node_modules/custom-library');
    await fs.mkdir(library,{recursive:true});
    await fs.writeFile(path.join(library,'package.json'),JSON.stringify({name:'custom-library',version:'1.0.0',main:'index.js'}));
    await fs.writeFile(path.join(library,'index.js'),"throw Error('must not import library')");
    assert.equal((await inspectDependencies(root,npmPath)).status,'ready');
    await fs.writeFile(path.join(library,'package.json'),JSON.stringify({name:'custom-library',version:'2.0.0'}));
    assert.equal((await inspectDependencies(root,npmPath)).status,'manifestMismatch');
    delete manifest.scripts.dev;
    await fs.writeFile(path.join(template,'package.json'),JSON.stringify(manifest));
    assert.match((await inspectDependencies(root,npmPath)).reason,/dev/);
  } finally {await fs.rm(root,{recursive:true,force:true});}
});
