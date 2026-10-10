import 'package:blog_studio/models/article_metadata.dart';
import 'package:blog_studio/models/markdown_path.dart';

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:blog_studio/services/blog_layout_service.dart';
import 'package:blog_studio/storage/file_store.dart';
import 'package:blog_studio/storage/front_matter_codec.dart';
import 'package:blog_studio/storage/path_guard.dart';

/// Current publication boundary: only images referenced by public content.
class PublicImages {
  static Future<Set<String>> referenced(String root) async {
    final store = FileStore(PathGuard(root));
    final manifest = await BlogLayoutService(root).manifest();
    final texts = <String>[];
    final canonicalRoot = await Directory(root).resolveSymbolicLinks();
    final posts = Directory(await store.guard.resolve('resource/posts'));
    if (await posts.exists()) {
      await for (final entity in posts.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is! File || !isMarkdownPath(entity.path)) continue;
        final relative = p
            .relative(entity.path, from: canonicalRoot)
            .split(p.separator)
            .join('/');
        if (relative.split('/').any((part) => part.startsWith('.'))) continue;
        final doc = FrontMatterDocument.parse(
          utf8.decode(await store.read(relative)),
        );
        ArticleMetadata.validate(doc.fields);
        if (doc.fields['published'] == false || doc.fields['draft'] == true) {
          continue;
        }
        texts.add(doc.body);
        texts.add(doc.fields['cover']?.toString() ?? '');
      }
    }
    final about = File(await store.guard.resolve('resource/about.md'));
    if (await about.exists()) {
      texts.add(FrontMatterDocument.parse(await about.readAsString()).body);
    }
    final site = manifest['site'] as Map? ?? {};
    texts.add(site['avatar']?.toString() ?? '');
    final config = jsonDecode(
      utf8.decode(
        await store.read(
          'template/${manifest['activeTemplate']}/template.json',
        ),
      ),
    ) as Map;
    for (final field in config['fields'] as List) {
      if (field['type'] == 'image' || field['type'] == 'text') {
        texts.add((field['value'] ?? field['default'] ?? '').toString());
      }
    }
    final names = <String>{};
    // Paths inserted by InkJian are URL-encoded and rooted at /img/.
    final pattern = RegExp(r'''(?:^|[\s("'<=\[])\/?img/([^\s"'<>\)\]\?#]+)''');
    for (final text in texts) {
      for (final match in pattern.allMatches(
        text.replaceAll(RegExp(r'<!--[\s\S]*?-->'), ''),
      )) {
        String name;
        try {
          name = Uri.decodeComponent(match[1]!);
        } on FormatException {
          continue;
        }
        if (name
                .split('/')
                .any((part) => part.isEmpty || part.startsWith('.')) ||
            name.contains('\\')) {
          continue;
        }
        names.add(name);
      }
    }
    return names;
  }
}
