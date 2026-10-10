import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:blog_studio/app/app_dependencies.dart';
import 'package:blog_studio/controllers/studio_controller.dart';
import 'package:blog_studio/services/editor_session.dart';
import 'package:blog_studio/storage/article_repository.dart';

import 'studio_controller_test.dart' show TestEditor, TestPrompts, TestPreview;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('opening and returning keep creation appearance stable and retain conflicts', () async {
    final root = await Directory.systemTemp.createTemp('inkjian-return-');
    final editor = TestEditor();
    final session = EditorSession(editor: editor);
    session.repository = ArticleRepository(root.path);
    await session.createArticle('文章');
    final path = session.article!.relativePath;
    final preview = TestPreview();
    final prompts = TestPrompts();
    final controller = StudioController(
      session: session,
      preview: preview,
      prompts: prompts,
      dependencies: AppDependencies.macos,
    );
    final states = <bool>[];
    var busySeen = false;
    void observe() {
      states.add(controller.creationBlocked);
      if (session.busy) {
        busySeen = true;
        unawaited(controller.newArticle());
        unawaited(controller.newNote());
      }
    }

    controller.addListener(observe);
    try {
      editor.type('返回前保存的正文');
      await controller.returnToLibrary();
      expect(busySeen, true);
      expect(states, everyElement(false));
      expect(session.article, isNull);
      expect(prompts.newArticleRequests, 0);
      expect(session.notes.articles, isEmpty);
      expect((await session.repository!.read(path)).bodySource, '返回前保存的正文');
      states.clear();
      await controller.openArticle(path);
      expect(session.article!.relativePath, path);
      expect(states, isNotEmpty);
      expect(states, everyElement(false));
      expect(prompts.newArticleRequests, 0);
      expect(session.notes.articles, isEmpty);
      states.clear();
      await File('${root.path}/$path').writeAsString('外部修改');
      editor.type('未保存的修改');
      await controller.returnToLibrary();
      expect(session.article!.relativePath, path);
      expect(session.body, '未保存的修改');
      expect(states, everyElement(false));
      expect(prompts.messages.last, contains('外部修改'));
      expect(prompts.newArticleRequests, 0);
      // Navigation flag must also reset after a failed save.
      session.busy = true;
      expect(controller.creationBlocked, true);
      session.busy = false;
    } finally {
      controller.removeListener(observe);
      controller.dispose();
      preview.dispose();
      session.dispose();
      await root.delete(recursive: true);
    }
  });
}
