import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support.dart';

import 'package:blog_studio/main.dart';
import 'package:blog_studio/ui/pages/studio_home.dart';
import 'package:blog_studio/models/image.dart';
import 'package:blog_studio/storage/trash_repository.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('local blog initializes, edits, saves images, publishes and recovers', (
    tester,
  ) async {
    final root = await Directory.systemTemp.createTemp('studio-native-blog-');
    final session = nativeTestSession();
    try {
      await tester.pumpWidget(const StudioApp());
      expect(find.text('从一个文件夹开始'), findsOneWidget);
      expect(await session.openProject(root.path, initialize: true), true);
      expect(session.index.articles, isEmpty);
      expect(await session.createArticle('原生本地流程'), true);
      await tester.pumpWidget(MaterialApp(home: StudioHome(session: session)));
      Map<String, dynamic>? editor;
      for (var i = 0; i < 150; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        if (session.nativeEditor.error != null) {
          fail(session.nativeEditor.error!);
        }
        if (session.nativeEditor.ready) {
          try {
            editor = await session.nativeEditor.inspect();
            break;
          } catch (_) {}
        }
      }
      expect(editor, isNotNull);
      await tester.tap(find.byTooltip('文章属性'));
      await tester.pumpAndSettle();
      final titleField = find.byType(TextField).first;
      await tester.tap(titleField);
      await tester.pump(const Duration(milliseconds: 200));
      final propertyFocus = await session.nativeEditor.nativeFocusState();
      expect(propertyFocus?['editorFocused'], false);
      expect(propertyFocus?['firstResponder'], isNot('none'));
      await tester.enterText(titleField, '标题焦点验证');
      await tester.pump(const Duration(milliseconds: 200));
      expect(session.attributes['title'], '标题焦点验证');
      await tester.tap(find.byTooltip('文章属性'));
      await tester.pumpAndSettle();
      expect(await session.nativeEditor.focus(), true);
      await session.nativeEditor.evaluate(
        "document.querySelector('.ProseMirror').focus(); document.execCommand('insertText', false, '本地保存正文'); true",
      );
      await tester.pump(const Duration(milliseconds: 200));
      session.updateAttributes({
        'tags': ['本地流程'],
        'categories': ['随笔'],
        'description': '本地摘要',
      });
      await session.insertImage(
        ImageInput(
          Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10]),
          name: 'bad.png',
        ),
      );
      // A corrupt image must leave the document unchanged and remain recoverable.
      expect(session.error, isNotNull);
      final pixel = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+ip1sAAAAASUVORK5CYII=',
      );
      await session.insertImage(ImageInput(pixel, name: 'test.png'));
      expect(
        session.error,
        isNull,
        reason: 'valid PNG import should decode and insert',
      );
      await tester.pump(const Duration(milliseconds: 500));
      final beforeCover = session.body;
      await session.setCover(ImageInput(pixel, name: 'cover.png'));
      expect(session.error, isNull);
      expect(session.body, beforeCover);
      expect(session.attributes['cover'], startsWith('/img/studio-'));
      await session.toggleTaxonomyPin('tags', '本地流程');
      expect(await session.flush(), true);
      final saved = await session.repository!.read(
        session.article!.relativePath,
      );
      expect(saved.bodySource, contains('本地保存正文'));
      expect(saved.bodySource, contains('/img/studio-'));
      expect(saved.bodySource, isNot(contains('data:image')));
      expect(saved.frontMatter['tags'], ['本地流程']);
      expect(saved.frontMatter['cover'], session.attributes['cover']);
      expect(await session.changeDraft(false), true);
      await tester.pump(const Duration(milliseconds: 500));
      expect(session.article!.draft, false);
      final source = await File('${root.path}/${session.article!.relativePath}')
          .readAsBytes();
      expect(await session.deleteArticle(), true);
      await tester.pump();
      final entry = (await TrashRepository(
        session.repository!.store,
      ).list()).single;
      expect(await session.restore(entry.id), true);
      expect(
        await File('${root.path}/${entry.originalPath}').readAsBytes(),
        source,
      );
      expect(await session.openArticle(entry.originalPath), true);
      await tester.pump(const Duration(milliseconds: 500));
      expect(session.body, contains('/img/studio-'));
      var imageVisible = false;
      for (var i = 0; i < 50; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        imageVisible =
            await session.nativeEditor.evaluate(
              "Array.from(document.images).some(image=>image.src.startsWith('data:image/png'))",
            ) ==
            true;
        if (imageVisible) break;
      }
      if (!imageVisible) {
        debugPrint('Reload document: ${await session.nativeEditor.inspect()}');
        debugPrint('Saved body: ${session.body}');
        debugPrint(
          'Reload status: ${session.nativeEditor.ready}, ${session.nativeEditor.error}, ${session.error}',
        );
        debugPrint(
          'Reload page: ${await session.nativeEditor.evaluate("JSON.stringify({htmlLength:document.body?.innerHTML.length,ready:document.readyState,studio:typeof window.studio})")}',
        );
        debugPrint(
          'Image state: ${await session.nativeEditor.evaluate("JSON.stringify(Array.from(document.images).map(image=>({src:image.getAttribute('src')?.substring(0,50),alt:image.alt})))")}',
        );
      }
      expect(imageVisible, true);
      final originalArticlePath = session.article!.relativePath;
      expect(await session.createNote(), true);
      await tester.pump(const Duration(milliseconds: 700));
      final notePath = session.article!.relativePath;
      await session.nativeEditor.insertMarkdown('**晚间素材**\n\n路边的小花');
      await tester.pump(const Duration(milliseconds: 500));
      expect(session.body, contains('晚间素材'));
      expect(
        jsonEncode((await session.nativeEditor.inspect())['document']),
        contains('strong'),
      );
      expect(await session.flush(), true);
      final originalNote = await File('${root.path}/$notePath').readAsBytes();
      expect(session.notes.articles.length, 1);
      expect(
        session.index.articles.any((a) => a.relativePath == notePath),
        false,
      );
      expect(await session.openArticle(originalArticlePath), true);
      await tester.pump(const Duration(milliseconds: 700));
      final beforeReference = session.body;
      await session.insertNote(notePath);
      await tester.pump(const Duration(milliseconds: 500));
      expect(session.error, isNull);
      expect(session.body, contains('晚间素材'));
      await session.nativeEditor.command('undo');
      await tester.pump(const Duration(milliseconds: 500));
      expect(session.body, beforeReference);
      expect(await File('${root.path}/$notePath').readAsBytes(), originalNote);
      expect(await session.deleteArticle(path: notePath), true);
      expect(session.notes.articles, isEmpty);
      final noteTrash = (await TrashRepository(
        session.repository!.store,
      ).list()).single;
      expect(await session.restore(noteTrash.id), true);
      expect(await File('${root.path}/$notePath').readAsBytes(), originalNote);
      final output = Directory('build/verification')
        ..createSync(recursive: true);
      File('${output.path}/local-blog-flow.json').writeAsStringSync(
        jsonEncode({
          'articles': session.index.articles.length,
          'body': session.body,
          'metadata': session.attributes,
          'imageFiles': await Directory('${root.path}/resource/images')
              .list()
              .length,
        }),
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    } finally {
      session.dispose();
      await root.delete(recursive: true);
    }
  });
}
