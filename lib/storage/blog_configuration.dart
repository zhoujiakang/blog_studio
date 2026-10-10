import 'dart:convert';

import 'package:blog_studio/storage/file_store.dart';
import 'package:blog_studio/models/blog_manifest.dart';

class BlogConfiguration {
  BlogConfiguration(this.document, this.hash);
  final Map<String, dynamic> document;
  final String hash;
  static const editableKeys = [
    'title',
    'subtitle',
    'author',
    'description',
    'avatar',
  ];
  Map<String, dynamic> get site =>
      Map<String, dynamic>.from(document['site'] as Map? ?? {});
  String value(String key) => site[key]?.toString() ?? '';
  static Future<BlogConfiguration> load(FileStore store) async {
    final bytes = await store.read('blog.json');
    final doc = BlogManifest.decode(bytes);
    doc['site'] ??= {};
    return BlogConfiguration(doc, contentHash(bytes));
  }

  BlogConfiguration change(String key, String value) {
    if (!editableKeys.contains(key)) throw const FormatException('通用配置字段无效');
    return BlogConfiguration({
      ...document,
      'site': {...site, key: value},
    }, hash);
  }

  Future<BlogConfiguration> save(FileStore store) async {
    final bytes = utf8.encode(
      '${const JsonEncoder.withIndent('  ').convert(document)}\n',
    );
    final hash = await store.write('blog.json', bytes, expectedHash: this.hash);
    return BlogConfiguration(document, hash);
  }
}
