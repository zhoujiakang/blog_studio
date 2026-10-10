class EditorChange {
  const EditorChange(this.revision, {this.composing = false});
  final int revision;
  final bool composing;
}
