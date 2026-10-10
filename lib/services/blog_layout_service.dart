import 'package:blog_studio/models/blog_manifest.dart';

import 'dart:convert';

import 'package:blog_studio/storage/resource_layout.dart';

import 'package:blog_studio/storage/file_store.dart';
import 'package:blog_studio/storage/path_guard.dart';
import 'package:blog_studio/storage/template_configuration.dart';

class BlogLayoutService {
  BlogLayoutService(String root) : store = FileStore(PathGuard(root));
  final FileStore store;
  static bool validId(String id) => BlogManifest.validTemplateId(id);
  Future<Map<String, dynamic>> manifest() async =>
      BlogManifest.decode(await store.read('blog.json'));

  Future<String> activeTemplate() async =>
      (await manifest())['activeTemplate'] as String;

  Future<void> activate(String id) async {
    if (!validId(id)) throw const FormatException('模板名称无效');
    final bytes = await store.read('blog.json');
    final value = await manifest();
    for (final file in [
      'template.json',
      'src/App.vue',
      'index.html',
      'package.json',
    ]) {
      await store.read(
        '${ResourceLayout(store.guard.root).templateDirectory}/$id/$file',
      );
    }
    final config = jsonDecode(
      utf8.decode(
        await store.read(
          '${ResourceLayout(store.guard.root).templateDirectory}/$id/template.json',
        ),
      ),
    );
    TemplateConfiguration.validate(Map<String, dynamic>.from(config as Map));
    if (config['id'] != id || config['formatVersion'] != 1) {
      throw const FormatException('模板配置无效');
    }
    value['activeTemplate'] = id;
    await store.write(
      'blog.json',
      utf8.encode(const JsonEncoder.withIndent('  ').convert(value)),
      expectedHash: contentHash(bytes),
    );
  }
}
