import { Crepe } from '@milkdown/crepe';
import { editorViewCtx, parserCtx, serializerCtx } from '@milkdown/kit/core';
import { $node, $remark, insert } from '@milkdown/kit/utils';
import { undo, redo } from '@milkdown/kit/prose/history';
import { TextSelection } from '@milkdown/kit/prose/state';
import { Fragment } from '@milkdown/kit/prose/model';
import { SourceCodec, preserveUnknown } from './source-codec';
import '@milkdown/crepe/theme/common/style.css';
import '@milkdown/crepe/theme/frame.css';
import './style.css';

const preserved = $node('studio_preserved', () => ({
  group: 'block',
  atom: true,
  selectable: true,
  attrs: { source: { default: '' } },
  toDOM: (node) => [
    'pre',
    { class: 'preserved-source', contenteditable: 'false', title: '原文保留片段' },
    node.attrs.source,
  ],
  parseDOM: [
    { tag: 'pre.preserved-source', getAttrs: (dom) => ({ source: dom.textContent }) },
  ],
  parseMarkdown: {
    match: (node) => node.type === 'studioPreserved',
    runner: (state, node, type) => state.addNode(type, { source: node.value }),
  },
  toMarkdown: {
    match: (node) => node.type.name === 'studio_preserved',
    runner: (state, node) => state.addNode('html', undefined, node.attrs.source),
  },
}));
const preserveRemark = $remark('studio-preserve-source', () => preserveUnknown);

let crepe,
  codec,
  session = '',
  revision = 0,
  opening = false,
  images = {};
let composing = false,
  pending = false,
  imageBookmark;
function send(type, fields = {}) {
  window.StudioBridge?.postMessage(
    JSON.stringify({ protocol: 1, type, session, revision, ...fields })
  );
}
function view() {
  return crepe.editor.action((ctx) => ctx.get(editorViewCtx));
}
function markdown() {
  return codec.encode(view().state.doc);
}
function changed() {
  if (opening) return;
  if (composing || view().composing) {
    pending = true;
    return;
  }
  pending = false;
  send('change', { markdown: markdown(), composing: false, revision: ++revision });
}

async function open(message) {
  opening = true;
  session = message.session;
  revision = message.revision ?? 0;
  images = message.images ?? {};
  composing = pending = false;
  imageBookmark = null;
  if (crepe) await crepe.destroy();
  document.querySelector('#editor').replaceChildren();
  codec = new SourceCodec();
  crepe = new Crepe({
    root: '#editor',
    defaultValue: message.markdown,
    features: {
      [Crepe.Feature.AI]: false,
      [Crepe.Feature.TopBar]: false,
      [Crepe.Feature.Toolbar]: false,
      [Crepe.Feature.BlockEdit]: false,
      [Crepe.Feature.Latex]: false,
      [Crepe.Feature.Table]: false,
    },
    featureConfigs: {
      [Crepe.Feature.Placeholder]: { text: '开始写作…' },
      [Crepe.Feature.ImageBlock]: {
        proxyDomURL: (url) => images[url] ?? 'data:,',
        onUpload: async () => {
          throw new Error('请通过桌面插图按钮导入图片');
        },
      },
    },
  });
  crepe.editor.use(preserved).use(preserveRemark);
  crepe.on((api) => api.updated(() => changed()));
  await crepe.create();
  crepe.editor.action((ctx) => {
    const doc = ctx.get(editorViewCtx).state.doc;
    codec.open(message.markdown, doc, ctx.get(parserCtx), (node) =>
      ctx.get(serializerCtx)(doc.copy(Fragment.from(node)))
    );
  });
  const dom = view().dom;
  dom.setAttribute('aria-label', 'Markdown 正文');
  dom.setAttribute('spellcheck', 'false');
  dom.addEventListener('compositionstart', () => {
    composing = true;
    send('composition', { composing: true });
  });
  dom.addEventListener('compositionend', () => {
    composing = false;
    setTimeout(() => {
      if (!opening && (pending || !view().composing)) changed();
    }, 30);
  });
  dom.addEventListener(
    'paste',
    (event) => {
      if (
        Array.from(event.clipboardData?.items ?? []).some((item) =>
          item.type.startsWith('image/')
        )
      ) {
        event.preventDefault();
        send('pasteImage');
      }
    },
    true
  );
  dom.addEventListener('keydown', (event) => {
    if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === 's') {
      event.preventDefault();
      send('save', { markdown: markdown() });
    }
  });
  opening = false;
  view().focus();
  send('opened', { markdown: message.markdown });
}

let queue = Promise.resolve();
window.studio = {
  receive(message) {
    queue = queue
      .then(async () => {
        if (message.type === 'open') return open(message);
        if (message.session !== session || !crepe) return;
        const v = view();
        if (message.type === 'undo') undo(v.state, v.dispatch);
        if (message.type === 'redo') redo(v.state, v.dispatch);
        if (message.type === 'focus') v.focus();
        if (message.type === 'bookmarkImage')
          imageBookmark = { doc: v.state.doc, selection: v.state.selection };
        if (message.type === 'image') {
          if (imageBookmark && !imageBookmark.doc.eq(v.state.doc))
            throw new Error('导入期间正文已变化，请重新插图');
          const selection = imageBookmark?.selection ?? v.state.selection;
          imageBookmark = null;
          if (
            !/^\/img\/[\w/.-]+$/.test(message.url) ||
            !/^data:image\/(png|jpeg|gif|webp);base64,/.test(message.data)
          )
            throw new Error('图片引用无效');
          images[message.url] = message.data;
          const type = v.state.schema.nodes['image-block'];
          v.dispatch(
            v.state.tr
              .setSelection(selection)
              .replaceSelectionWith(type.create({ src: message.url }))
              .scrollIntoView()
          );
          v.focus();
        }
        if (message.type === 'insertMarkdown') {
          if (composing || v.composing) throw new Error('请先完成输入法选字，再引用小记');
          images = { ...images, ...message.images };
          crepe.editor.action(insert(message.markdown));
          v.focus();
        }
        if (message.type === 'snapshot')
          send('snapshot', {
            markdown: markdown(),
            composing: composing || v.composing,
            request: message.request,
          });
      })
      .catch((error) => send('error', { message: error.message }));
  },
  // Native integration tests inspect state rather than assuming a screenshot proves conversion.
  inspect: () => ({
    session,
    revision,
    composing,
    markdown: markdown(),
    document: view().state.doc.toJSON(),
  }),
};
send('ready');
