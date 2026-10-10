import { test } from 'node:test';
import assert from 'node:assert/strict';
import { Schema } from '@milkdown/kit/prose/model';
import { SourceCodec, sourceParts, preserveUnknown } from '../src/source-codec.js';
import { unified } from 'unified';
import remarkParse from 'remark-parse';

const schema = new Schema({
  nodes: { doc: { content: 'paragraph*' }, paragraph: { content: 'text*' }, text: {} },
});
const paragraph = (text) =>
  schema.nodes.paragraph.create(null, text ? schema.text(text) : null);
const doc = (nodes) => schema.nodes.doc.create(null, nodes);
const parse = (text) => doc([paragraph(text.replace(/\*\*/g, ''))]);

test('unchanged full source retains CRLF, leading/trailing blanks and syntax', () => {
  const source = '\r\n**中文**\r\n\r\n尾段\r\n';
  const initial = doc([paragraph('中文'), paragraph('尾段')]);
  const codec = new SourceCodec();
  codec.open(source, initial, parse, (node) => node.textContent);
  assert.equal(codec.encode(initial), source);
});

test('editing a neighbor preserves untouched original spelling and separator', () => {
  const initial = doc([paragraph('重点'), paragraph('尾段')]);
  const codec = new SourceCodec();
  codec.open('**重点**\r\n\r\n\r\n尾段', initial, parse, (node) => node.textContent);
  assert.equal(
    codec.encode(doc([paragraph('重点'), paragraph('新内容')])),
    '**重点**\r\n\r\n\r\n新内容'
  );
});

test('a fenced code block with internal blank lines stays one source segment', () => {
  const parts = sourceParts('```js\n# literal\n\n**literal**\n```\n\n末尾');
  assert.equal(parts.length, 2);
  assert.match(parts[0].text, /\n\n\*\*literal/);
});

test('unknown HTML/template/math becomes inert source; fenced text is untouched', () => {
  const source = '<!-- more -->\n\n{{ template }}\n\n$math$\n\n```\n{{ code }}\n```';
  const tree = unified().use(remarkParse).parse(source);
  preserveUnknown()(tree, source);
  assert.deepEqual(
    tree.children.map((n) => n.type),
    ['studioPreserved', 'studioPreserved', 'studioPreserved', 'code']
  );
  assert.equal(tree.children[0].value, '<!-- more -->');
});

test('deleting an untouched block removes its source instead of resurrecting it', () => {
  const initial = doc([paragraph('one'), paragraph('two')]);
  const codec = new SourceCodec();
  codec.open('one\n\ntwo', initial, parse, (node) => node.textContent);
  assert.equal(codec.encode(doc([paragraph('two')])), 'two');
});

test('identical blocks keep their own source spelling after deleting a sibling', () => {
  const first = paragraph('same'),
    second = paragraph('same');
  const initial = doc([first, second]);
  const codec = new SourceCodec();
  codec.open(
    '**same**\n\n__same__',
    initial,
    (text) => doc([paragraph(text.replace(/\*\*|__/g, ''))]),
    (node) => node.textContent
  );
  assert.equal(codec.encode(doc([second])), '__same__');
});

test('synthetic image nodes without source positions remain valid', () => {
  const image = { type: 'image-block', url: '/img/test.png', title: null };
  const tree = { type: 'root', children: [image] };
  preserveUnknown()(tree, '![](/img/test.png)');
  assert.equal(tree.children[0], image);
  assert.equal(image.title, '');
});
