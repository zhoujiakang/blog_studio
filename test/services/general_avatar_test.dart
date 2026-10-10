import 'package:blog_studio/controllers/web_markdown_controller.dart';

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:blog_studio/models/image.dart';
import 'package:blog_studio/models/project.dart';
import 'package:blog_studio/services/editor_session.dart';
import 'package:blog_studio/storage/article_repository.dart';
import 'package:blog_studio/storage/blog_configuration.dart';
import 'package:blog_studio/storage/resource_layout.dart';

import '../storage/image_importer_test.dart' show tinyPng;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('avatar import saves shared image and survives reopening; removal preserves the image', () async {
    final root = await Directory.systemTemp.createTemp('inkjian-avatar-');
    final session = EditorSession(editor: WebMarkdownController());
    try {
      await File('${root.path}/blog.json').writeAsString(
        jsonEncode({
          'formatVersion': 2,
          'activeTemplate': 'butterfly',
          'site': {'author': '作者', 'custom': '保留'},
          'publish': {'workspaceId': 'keep'},
        }),
      );
      session.project = ProjectSession(root: root.path);
      session.repository = ArticleRepository(root.path);
      session.general.load(
        await BlogConfiguration.load(session.repository!.store),
      );
      final bytes = await tinyPng();
      await session.setGeneralAvatar(ImageInput(bytes, name: 'avatar.png'));
      expect(session.error, isNull);
      final url = session.generalConfiguration!.value('avatar');
      expect(url, startsWith('/img/'));
      expect(await session.flush(), true);
      final stored = await BlogConfiguration.load(session.repository!.store);
      expect(stored.value('avatar'), url);
      expect(stored.site['custom'], '保留');
      expect(stored.document['publish'], {'workspaceId': 'keep'});
      final path = ResourceLayout(root.path).imagePath(url);
      expect(await session.repository!.store.read(path), bytes);
      await session.setGeneralAvatar(
        ImageInput(Uint8List.fromList([1, 2]), name: 'invalid.png'),
      );
      expect(session.error, isNotNull);
      expect(session.generalConfiguration!.value('avatar'), url);
      session.updateGeneralConfiguration('avatar', '');
      expect(await session.flush(), true);
      expect(
        (await BlogConfiguration.load(session.repository!.store))
            .value('avatar'),
        '',
      );
      expect(await File('${root.path}/$path').exists(), true);
    } finally {
      session.dispose();
      await root.delete(recursive: true);
    }
  });
}
