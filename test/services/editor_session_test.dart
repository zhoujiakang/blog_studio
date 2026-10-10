import 'package:blog_studio/controllers/web_markdown_controller.dart';

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:blog_studio/services/editor_session.dart';
import 'package:blog_studio/models/article.dart';
import 'package:blog_studio/models/project.dart';
import 'package:blog_studio/models/save_state.dart';
import 'package:blog_studio/storage/article_repository.dart';
import 'package:blog_studio/storage/trash_repository.dart';

class FakeEditor extends WebMarkdownController {
  void type(String body) {
    protocol.markdown = body;
    notifyListeners();
  }
}

class SlowRepository extends ArticleRepository {
  SlowRepository(super.root);
  Completer<void>? hold;
  int scans = 0;
  @override
  Future<ArticleIndex> scan({bool notes = false}) {
    scans++;
    return super.scan(notes: notes);
  }

  @override
  Future<ArticleSnapshot> save(
    ArticleSnapshot original,
    String body,
    Map<String, dynamic> changes,
  ) async {
    final gate = hold;
    hold = null;
    if (gate != null) await gate.future;
    return super.save(original, body, changes);
  }
}

void main() {
  late Directory root;
  late FakeEditor editor;
  late EditorSession session;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('studio-session-test-');
    editor = FakeEditor();
    session = EditorSession(editor: editor);
    session.project = ProjectSession(root: root.path);
    session.repository = SlowRepository(root.path);
    expect(await session.createArticle('本地写作'), true);
  });
  tearDown(() async {
    session.dispose();
    await root.delete(recursive: true);
  });
  test(
    'automatic save captures latest text and attributes during slow write',
    () async {
      final repo = session.repository! as SlowRepository;
      final gate = Completer<void>();
      repo.hold = gate;
      editor.type('第一版\n');
      final saving = session.flush();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      editor.type('第二版\n');
      session.updateAttributes({
        'tags': ['中文'],
      });
      gate.complete();
      expect(await saving, true);
      expect(session.dirty, false);
      expect(session.status, SaveStatus.clean);
      final disk = await repo.read(session.article!.relativePath);
      expect(disk.bodySource, '第二版\n');
      expect(disk.frontMatter['tags'], ['中文']);
      editor.type('自动保存\n');
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      expect(
        (await repo.read(session.article!.relativePath)).bodySource,
        '自动保存\n',
      );
    },
  );
  test(
    'local saves update the index without scanning unrelated documents',
    () async {
      final repo = session.repository! as SlowRepository;
      final initialScans = repo.scans;
      session.index = ArticleIndex(
        session.index.articles,
        errors: {'resource/posts/broken.md': 'bad YAML'},
      );
      editor.type('可搜索的新正文');
      session.updateAttributes({
        'title': '新标题',
        'tags': ['新增标签'],
        'categories': ['技术/Flutter'],
      });
      expect(await session.flush(), true);
      final saved = session.index.articles.single;
      expect(saved.title, '新标题');
      expect(saved.searchText, contains('可搜索的新正文'));
      expect(saved.tags, ['新增标签']);
      expect(saved.categories, ['技术/Flutter']);
      expect(session.index.errors, contains('resource/posts/broken.md'));
      expect(await session.flush(), true);
      expect(repo.scans, initialScans);
      final other = await repo.create('外部新文档');
      expect(session.index.articles, hasLength(1));
      await session.refresh();
      expect(repo.scans, initialScans + 2);
      expect(
        session.index.articles.map((a) => a.relativePath),
        contains(other.relativePath),
      );
      final beforeNavigation = repo.scans;
      expect(await session.changeDraft(false), true);
      expect(
        session.index.articles.where((a) => a.title == '新标题').single.draft,
        false,
      );
      expect(await session.deleteArticle(), true);
      expect(session.index.articles, hasLength(1));
      expect(repo.scans, beforeNavigation);
    },
  );

  test('About and clean flush do not rescan the article library', () async {
    final repo = session.repository! as SlowRepository;
    final scans = repo.scans;
    final indexRevision = session.indexRevision;
    expect(await session.openAbout(), true);
    editor.type('# 新关于');
    expect(await session.flush(), true);
    expect(session.indexRevision, indexRevision);
    expect(repo.scans, scans);
    expect(session.index.articles, hasLength(1));
  });

  test(
    'conflict prevents switching or deleting and keeps recoverable user input',
    () async {
      final first = session.article!;
      final second = await session.repository!.create('另一篇');
      await File('${root.path}/${first.relativePath}').writeAsString('外部版本\n');
      editor.type('我未保存的正文\n');
      expect(await session.openArticle(second.relativePath), false);
      expect(session.article!.relativePath, first.relativePath);
      expect(session.body, '我未保存的正文\n');
      expect(session.status, SaveStatus.conflict);
      expect(await session.deleteArticle(), false);
      expect(
        await File('${root.path}/${first.relativePath}').readAsString(),
        '外部版本\n',
      );
      await session.reload();
      expect(session.body, '外部版本\n');
      expect(session.dirty, false);
    },
  );
  test(
    'library actions change draft and trash without opening the editor',
    () async {
      final original = session.article!;
      editor.type('保留正文\n');
      expect(await session.closeArticle(), true);
      expect(
        await session.changeDraft(!original.draft, path: original.relativePath),
        true,
      );
      expect(session.article, isNull);
      final changed = session.index.articles.single;
      expect(changed.draft, !original.draft);
      expect(
        (await session.repository!.read(changed.relativePath)).bodySource,
        '保留正文\n',
      );
      expect(await session.deleteArticle(path: changed.relativePath), true);
      expect(session.article, isNull);
      expect(session.index.articles, isEmpty);
      expect(
        await File('${root.path}/${changed.relativePath}').exists(),
        false,
      );
    },
  );

  test(
    'library filter switching does not pulse busy or refresh the index',
    () async {
      expect(await session.closeArticle(), true);
      final initialIndexRevision = session.indexRevision;
      final busyStates = <bool>[];
      session.addListener(() => busyStates.add(session.busy));
      for (var i = 0; i < 3; i++) {
        expect(await session.closeArticle(), true);
      }
      expect(busyStates, isEmpty);
      expect(session.indexRevision, initialIndexRevision);
      session.importing = true;
      expect(await session.closeArticle(), false);
      session.importing = false;
      session.busy = true;
      expect(await session.closeArticle(), false);
      session.busy = false;
    },
  );
  test(
    'notes use the same session but stay separate and recover byte for byte',
    () async {
      final post = session.article!;
      expect(await session.createNote(), true);
      final notePath = session.article!.relativePath;
      expect(notePath, startsWith('resource/notes/'));
      editor.type('# 路边的小事\n\n**今天很开心**\n');
      expect(await session.flush(), true);
      expect(session.notes.articles.single.title, '路边的小事');
      expect(session.index.articles.single.relativePath, post.relativePath);
      expect(session.notes.articles.single.draft, false);
      expect(session.article!.frontMatter.containsKey('title'), false);
      expect(session.article!.frontMatter['updated'], isNotNull);
      final source = await File('${root.path}/$notePath').readAsBytes();
      expect(await session.changeDraft(true), false);
      expect(session.article!.relativePath, notePath);
      expect(await session.closeArticle(), true);
      expect(await session.deleteArticle(path: notePath), true);
      expect(session.notes.articles, isEmpty);
      final entry = (await TrashRepository(
        session.repository!.store,
      ).list()).single;
      expect(await session.restore(entry.id), true);
      expect(await File('${root.path}/$notePath').readAsBytes(), source);
      expect(await session.openArticle(notePath), true);
      expect(session.body, contains('**今天很开心**'));
    },
  );

  test(
    'external changes to a note block switching and retain unsaved input',
    () async {
      expect(await session.createNote(), true);
      final note = session.article!;
      await File('${root.path}/${note.relativePath}').writeAsString('外部小记\n');
      editor.type('没有保存的小记\n');
      expect(await session.closeArticle(), false);
      expect(session.body, '没有保存的小记\n');
      expect(session.status, SaveStatus.conflict);
      expect(
        await File('${root.path}/${note.relativePath}').readAsString(),
        '外部小记\n',
      );
    },
  );
}
