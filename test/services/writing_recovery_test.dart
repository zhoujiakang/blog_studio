import 'dart:io';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:blog_studio/services/editor_session.dart';
import 'package:blog_studio/storage/recovery_store.dart';
import 'package:blog_studio/storage/article_repository.dart';
import 'package:blog_studio/models/project.dart';
import 'package:blog_studio/models/save_state.dart';

import 'editor_session_test.dart' show FakeEditor;

void main() {
  late Directory root;
  late EditorSession session;
  late FakeEditor editor;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('inkjian-recovery-');
    editor = FakeEditor();
    session = EditorSession(editor: editor)
      ..project = ProjectSession(root: root.path)
      ..repository = ArticleRepository(root.path);
    expect(await session.createArticle('安全写作'), true);
  });
  tearDown(() async {
    await session.preservePendingEdits();
    session.dispose();
    await root.delete(recursive: true);
  });
  test(
    'unsaved body and metadata survive a new session without overwriting disk',
    () async {
      final path = session.article!.relativePath;
      editor.type('还没自动保存的**中文**');
      session.updateAttributes({
        'tags': ['恢复标签'],
      });
      await session.preservePendingEdits();
      session.dispose();
      editor = FakeEditor();
      session = EditorSession(editor: editor)
        ..project = ProjectSession(root: root.path)
        ..repository = ArticleRepository(root.path);
      expect(
        await RecoveryStore(session.repository!.store).list(),
        hasLength(1),
      );
      expect(
        (await session.repository!.read(path)).bodySource,
        isNot(contains('中文')),
      );
      expect(await session.openArticle(path), true);
      expect(session.recovered, true);
      expect(session.body, '还没自动保存的**中文**');
      expect(session.attributes['tags'], ['恢复标签']);
      expect(await session.flush(), true);
      expect(await RecoveryStore(session.repository!.store).list(), isEmpty);
      expect((await session.repository!.read(path)).bodySource, contains('中文'));
    },
  );
  test(
    'proactive external edit detection keeps both versions and supports copy',
    () async {
      final path = session.article!.relativePath;
      editor.type('我的未保存内容');
      await session.preservePendingEdits();
      final external = File('${root.path}/$path');
      await external.writeAsString('外部编辑器的版本');
      await session.checkExternalChanges();
      expect(session.status, SaveStatus.conflict);
      expect(session.body, '我的未保存内容');
      expect(await session.flush(), false);
      expect(await session.saveCopy(), true);
      expect(await external.readAsString(), '外部编辑器的版本');
      expect(session.article!.relativePath, isNot(path));
      expect(session.article!.bodySource, '我的未保存内容');
    },
  );
  test(
    'deleted originals and damaged records do not erase recoverable content',
    () async {
      final path = session.article!.relativePath;
      editor.type('删除后仍能恢复');
      await session.preservePendingEdits();
      await File('${root.path}/$path').delete();
      await File('${root.path}/.blog-studio/recovery/broken.json')
          .writeAsString('bad json');
      session.dispose();
      editor = FakeEditor();
      session = EditorSession(editor: editor)
        ..project = ProjectSession(root: root.path)
        ..repository = ArticleRepository(root.path);
      expect(await session.openArticle(path), true);
      expect(session.recovered, true);
      expect(session.recoveryError, isNotNull);
      await session.checkExternalChanges();
      expect(await session.saveCopy(), true);
      expect(session.article!.bodySource, '删除后仍能恢复');
      expect(
        await File('${root.path}/.blog-studio/recovery/broken.json').exists(),
        true,
      );
    },
  );
  test(
    'successful saves retain a prior version without a management page',
    () async {
      final path = session.article!.relativePath;
      editor.type('第一个保存版本');
      expect(await session.flush(), true);
      editor.type('第二个保存版本');
      expect(await session.flush(), true);
      final backup = File('${root.path}/.blog-studio/backups/$path');
      expect(await backup.readAsString(), contains('第一个保存版本'));
      expect(await RecoveryStore(session.repository!.store).list(), isEmpty);
    },
  );
  test(
    'opening a blog reconnects the latest pending edit automatically',
    () async {
      await File('${root.path}/blog.json').writeAsString(
        jsonEncode({
          'formatVersion': 2,
          'activeTemplate': 'minimal',
          'site': {},
        }),
      );
      final theme = Directory('${root.path}/template/minimal');
      await Directory('${theme.path}/src').create(recursive: true);
      for (final path in ['src/App.vue', 'index.html', 'package.json']) {
        await File('${theme.path}/$path').writeAsString('{}');
      }
      await File('${theme.path}/template.json').writeAsString(
        jsonEncode({
          'formatVersion': 1,
          'id': 'minimal',
          'name': 'Minimal',
          'fields': [],
        }),
      );
      editor.type('自动接回的内容');
      await session.preservePendingEdits();
      session.dispose();
      editor = FakeEditor();
      session = EditorSession(editor: editor);
      expect(await session.openProject(root.path), true, reason: session.error);
      expect(session.body, '自动接回的内容');
      expect(session.recovered, true);
      expect(session.externalChange, false);
    },
  );
  test('a journal left after a completed save is silently cleared', () async {
    final original = session.article!;
    final attrs = Map<String, dynamic>.from(session.attributes);
    await session.repository!.save(original, '已保存内容', attrs);
    await RecoveryStore(session.repository!.store)
        .checkpoint(RecoveryRecord(original, '已保存内容', attrs, DateTime.now()));
    session.dispose();
    editor = FakeEditor();
    session = EditorSession(editor: editor)
      ..project = ProjectSession(root: root.path)
      ..repository = ArticleRepository(root.path);
    expect(await session.openArticle(original.relativePath), true);
    expect(session.recovered, false);
    expect(session.status, SaveStatus.clean);
    expect(await RecoveryStore(session.repository!.store).list(), isEmpty);
  });
}
