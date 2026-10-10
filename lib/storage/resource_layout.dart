import 'dart:convert';
import 'dart:io';

/// The only supported blog layout: blog.json + resource/ + template/.
class ResourceLayout {
  ResourceLayout(this.root);
  final String root;
  String get templateDirectory => 'template';
  String get posts => 'resource/posts';
  String get drafts => 'resource/drafts';
  String get notes => 'resource/notes';
  String get images => 'resource/images';
  String get about => 'resource/about.md';
  String get activeTemplate {
    final doc = jsonDecode(File('$root/blog.json').readAsStringSync());
    if (doc is! Map ||
        doc['formatVersion'] != 2 ||
        doc['activeTemplate'] is! String ||
        !RegExp(r'^[a-zA-Z0-9\u4e00-\u9fff][a-zA-Z0-9_\u4e00-\u9fff-]*$')
            .hasMatch(doc['activeTemplate'])) {
      throw const FormatException(
        '仅支持 blog.json + resource/ + template/ 的博客格式。',
      );
    }
    return doc['activeTemplate'] as String;
  }

  String get packageRoot => '$root/template/$activeTemplate';
  String imagePath(String url) {
    if (!url.startsWith('/img/')) throw const FormatException('图片路径无效');
    return '$images/${url.substring(5)}';
  }
}
