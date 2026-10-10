import { unified } from 'unified';
import remarkParse from 'remark-parse';

const astParser = unified().use(remarkParse);
export function sourceParts(source) {
  const children = astParser.parse(source).children;
  return children.map((node, i) => ({
    text: source.slice(node.position.start.offset, node.position.end.offset),
    separator: source.slice(
      node.position.end.offset,
      children[i + 1]?.position.start.offset ?? source.length
    ),
    prefix: i === 0 ? source.slice(0, node.position.start.offset) : '',
  }));
}

// Unknown syntax remains selectable plain text, never executable HTML.
export function preserveUnknown() {
  return (tree, file) => {
    const source = String(file);
    // Markdown images without a caption have title:null. The locked Crepe
    // image-block schema requires a string; its parser otherwise drops them.
    const normalizeImages = (node) => {
      if ((node.type === 'image' || node.type === 'image-block') && node.title == null)
        node.title = '';
      (node.children ?? []).forEach(normalizeImages);
    };
    normalizeImages(tree);
    tree.children = tree.children.map((node) => {
      // Crepe may synthesize image nodes without source positions before this plugin.
      if (!node.position?.start || !node.position?.end) return node;
      const raw = source.slice(node.position.start.offset, node.position.end.offset);
      const hasHtml = (n) => n.type === 'html' || (n.children ?? []).some(hasHtml);
      if (
        hasHtml(node) ||
        node.type === 'table' ||
        node.type === 'definition' ||
        (node.type !== 'code' &&
          /\{%|\{\{|\$\$|\$[^$\n]+\$|\[[^\]]+\]\[[^\]]*\]/.test(raw))
      ) {
        return { type: 'studioPreserved', value: raw, position: node.position };
      }
      return node;
    });
  };
}

export class SourceCodec {
  open(source, doc, parse, serialize) {
    this.source = source;
    this.initial = doc;
    this.serializeNode = serialize;
    this.newline = source.includes('\r\n') ? '\r\n' : '\n';
    this.parts = sourceParts(source).map((part) => ({ ...part, doc: parse(part.text) }));
    const assigned = new Set();
    doc.forEach((node) => {
      const index = this.parts.findIndex(
        (part, i) =>
          !assigned.has(i) && part.doc.childCount === 1 && node.eq(part.doc.child(0))
      );
      if (index >= 0) {
        this.parts[index].reference = node;
        assigned.add(index);
      }
    });
  }

  encode(doc) {
    if (doc.eq(this.initial)) return this.source;
    const used = new Set();
    const children = [];
    doc.forEach((node) => children.push(node));
    let result = this.parts[0]?.prefix ?? '';
    children.forEach((node, index) => {
      const match =
        this.parts.find((part, i) => !used.has(i) && part.reference === node) ??
        this.parts.find(
          (part, i) =>
            !used.has(i) && part.doc.childCount === 1 && node.eq(part.doc.child(0))
        );
      if (match) {
        used.add(this.parts.indexOf(match));
        result += match.text;
        result +=
          match.separator || (index < children.length - 1 ? this.newline.repeat(2) : '');
      } else {
        result += this.serializeNode(node).trimEnd().replace(/\r?\n/g, this.newline);
        if (index < children.length - 1) result += this.newline.repeat(2);
      }
    });
    return result;
  }
}
