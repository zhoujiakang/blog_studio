import 'dart:convert';

import 'package:blog_studio/storage/resource_layout.dart';

import 'package:blog_studio/storage/file_store.dart';
import 'package:blog_studio/models/blog_manifest.dart';

class TemplateConfiguration {
  TemplateConfiguration(this.path, this.document, this.hash);
  final String path;
  final Map<String, dynamic> document;
  final String hash;
  String get name => document['name'] as String;
  List<Map<String, dynamic>> get fields => (document['fields'] as List)
      .map((e) => Map<String, dynamic>.from(e as Map))
      .toList();
  String value(Map<String, dynamic> field) =>
      (field['value'] ?? field['default'] ?? '').toString();
  static void validate(Map<String, dynamic> doc) {
    if (doc['formatVersion'] != 1 ||
        doc['id'] is! String ||
        !BlogManifest.validTemplateId(doc['id']) ||
        doc['name'] is! String ||
        doc['fields'] is! List) {
      throw const FormatException('模板配置格式不支持。');
    }
    final keys = <String>{};
    for (final field in doc['fields'] as List) {
      if (field is! Map ||
          field['key'] is! String ||
          !RegExp(r'^[a-zA-Z][a-zA-Z0-9_]*$').hasMatch(field['key']) ||
          !keys.add(field['key']) ||
          field['label'] is! String ||
          field['type'] is! String) {
        throw const FormatException('模板字段无效或名称重复。');
      }
      if (['text', 'image', 'color'].contains(field['type'])) {
        if (field['default'] is! String) {
          throw const FormatException('配置字段需要文字形式的默认值。');
        }
        for (final key in ['default', 'value']) {
          if (field.containsKey(key)) validateValue(field['type'], field[key]);
        }
      }
    }
  }

  static void validateValue(String type, dynamic value) {
    if (value is! String) throw const FormatException('配置值必须是文字。');
    if (type == 'color' && !RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(value)) {
      throw const FormatException('颜色格式应为 #RRGGBB。');
    }
    if (type == 'image' &&
        value.isNotEmpty &&
        (!RegExp(r'^/img/[\w/.-]+$').hasMatch(value) ||
            value.split('/').contains('..'))) {
      throw const FormatException('图片必须来自公共资源目录。');
    }
  }

  static Future<TemplateConfiguration> load(FileStore store) async {
    final id =
        BlogManifest.decode(await store.read('blog.json'))['activeTemplate']
            as String;
    final path =
        '${ResourceLayout(store.guard.root).templateDirectory}/$id/template.json';
    final bytes = await store.read(path);
    final doc = Map<String, dynamic>.from(
      jsonDecode(utf8.decode(bytes)) as Map,
    );
    validate(doc);
    if (doc['id'] != id) throw const FormatException('模板目录与配置 ID 不一致。');
    return TemplateConfiguration(path, doc, contentHash(bytes));
  }

  TemplateConfiguration change(String key, String value) {
    final copy = Map<String, dynamic>.from(
      jsonDecode(jsonEncode(document)) as Map,
    );
    final field = (copy['fields'] as List).cast<Map>().firstWhere(
      (e) => e['key'] == key,
    );
    if (!['text', 'image', 'color'].contains(field['type'])) {
      throw const FormatException('不支持此字段类型');
    }
    validateValue(field['type'], value);
    field['value'] = value;
    return TemplateConfiguration(path, copy, hash);
  }

  TemplateConfiguration defaults() {
    var next = this;
    for (final field in fields) {
      if (['text', 'image', 'color'].contains(field['type'])) {
        next = next.change(field['key'], (field['default'] ?? '').toString());
      }
    }
    return next;
  }

  Future<TemplateConfiguration> save(FileStore store) async {
    validate(document);
    final bytes = utf8.encode(
      '${const JsonEncoder.withIndent('  ').convert(document)}\n',
    );
    final nextHash = await store.write(path, bytes, expectedHash: hash);
    return TemplateConfiguration(path, document, nextHash);
  }
}
