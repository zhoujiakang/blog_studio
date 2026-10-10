import 'package:blog_studio/controllers/web_markdown_controller.dart';

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:blog_studio/services/blog_layout_service.dart';
import 'package:blog_studio/storage/article_repository.dart';
import 'package:blog_studio/services/project_service.dart';
import 'package:blog_studio/services/template_installer.dart';
import 'package:blog_studio/storage/template_configuration.dart';
import 'package:blog_studio/storage/trash_repository.dart';
import 'package:blog_studio/services/editor_session.dart';
import 'package:blog_studio/models/save_state.dart';

void main() {
  late Directory root;
  final installer = TemplateInstaller(
    readAsset: (path) => File(path).readAsBytes(),
  );
  Future<void> seed() => installer.initialize(root.path);
  setUp(() async {
    root = await Directory.systemTemp.createTemp('studio-shared-test-');
  });
  tearDown(() async {
    await root.delete(recursive: true);
  });

  test('current resources support posts, drafts, notes and About without old copies', () async {
    await seed();
    final service = ProjectService(installer: installer);
    await service.open(root.path);
    final repo = ArticleRepository(root.path);
    var draft = await repo.create('新草稿');
    expect(draft.relativePath, startsWith('resource/drafts/'));
    draft = await repo.setDraft(draft, false);
    expect(draft.relativePath, startsWith('resource/posts/'));
    final note = await repo.createNote();
    expect(note.note, true);
    final about = await repo.openAbout();
    expect(about.about, true);
    await repo.save(about, '# 我的介绍\n', {});
    final trash = TrashRepository(repo.store);
    await trash.remove(note);
    await trash.restore((await trash.list()).single);
    expect(
      (await repo.read(note.relativePath)).originalBytes,
      note.originalBytes,
    );
    await expectLater(trash.remove(about), throwsFormatException);
    for (final path in ['source', 'resources', 'templates']) {
      expect(await Directory('${root.path}/$path').exists(), false);
    }
  });
  test(
    'old layout is rejected without migration or modifying user files',
    () async {
      final original = File('${root.path}/source/_posts/custom.md');
      await original.parent.create(recursive: true);
      await original.writeAsString('旧正文');
      final service = ProjectService(installer: installer);
      await expectLater(service.open(root.path), throwsException);
      expect(await original.readAsString(), '旧正文');
      expect(await File('${root.path}/blog.json').exists(), false);
      expect(await Directory('${root.path}/resource').exists(), false);
      final marker = File('${root.path}/blog.json');
      const old = '{"formatVersion":1,"activeTemplate":"butterfly"}';
      await marker.writeAsString(old);
      await expectLater(service.open(root.path), throwsException);
      await expectLater(
        BlogLayoutService(root.path).manifest(),
        throwsFormatException,
      );
      expect(await marker.readAsString(), old);
      final repo = ArticleRepository(root.path);
      await expectLater(repo.read('source/_posts/custom.md'), throwsException);
      await expectLater(
        repo.read('resources/posts/custom.md'),
        throwsException,
      );
      expect((await repo.scan()).articles, isEmpty);
    },
  );
  test('configuration validates values, preserves unknown data, resets and detects external edits', () async {
    await ProjectService(installer: installer).initialize(root.path);
    final repo = ArticleRepository(root.path);
    var config = await TemplateConfiguration.load(repo.store);
    final extended =
        jsonDecode(jsonEncode(config.document)) as Map<String, dynamic>;
    extended['future'] = {'keep': true};
    (extended['fields'] as List).add({
      'key': 'futureSetting',
      'label': '未来功能',
      'type': 'future',
      'value': {'keep': 42},
    });
    config = await TemplateConfiguration(
      config.path,
      extended,
      config.hash,
    ).save(repo.store);
    config = await config
        .change('themeColor', '#123ABC')
        .change('announcement', '中文公告\n第二行')
        .save(repo.store);
    expect(config.document['future'], {'keep': true});
    expect(config.fields.last['value'], {'keep': 42});
    expect(() => config.change('themeColor', 'red'), throwsFormatException);
    expect(
      () => config.change('backgroundImage', '/img/../secret.png'),
      throwsFormatException,
    );
    expect(
      () => config.change('backgroundImage', 'https://example.com/a.png'),
      throwsFormatException,
    );
    final restored = config.defaults();
    expect(
      restored.value(
        restored.fields.firstWhere((f) => f['key'] == 'themeColor'),
      ),
      '#87968B',
    );
    expect(restored.fields.last['value'], {'keep': 42});
    final disk = File('${root.path}/${config.path}');
    await disk.writeAsString('${await disk.readAsString()}\n');
    await expectLater(
      config.change('announcement', '不应覆盖').save(repo.store),
      throwsA(isA<Exception>()),
    );
    expect(await disk.readAsString(), isNot(contains('不应覆盖')));
  });
  test('switching styles preserves shared articles and independent settings; each theme has independent dependencies', () async {
    await ProjectService(installer: installer).initialize(root.path);
    final repo = ArticleRepository(root.path);
    final post = await repo.create('保留的文章');
    var first = await TemplateConfiguration.load(repo.store);
    first = await first.change('themeColor', '#AABBCC').save(repo.store);
    final dest = Directory('${root.path}/template/minimal');
    await dest.create();
    await for (final entry in Directory(
      '${root.path}/template/butterfly',
    ).list(recursive: true, followLinks: false)) {
      if (entry is! File) continue;
      final relative = entry.path.substring(
        '${root.path}/template/butterfly/'.length,
      );
      final target = File('${dest.path}/$relative');
      await target.parent.create(recursive: true);
      await entry.copy(target.path);
    }
    final secondFile = File('${dest.path}/template.json');
    final second = jsonDecode(await secondFile.readAsString()) as Map;
    second['id'] = 'minimal';
    second['name'] = '简约';
    for (final f in second['fields']) {
      if (f['key'] == 'themeColor') f['value'] = '#112233';
    }
    await secondFile.writeAsString(jsonEncode(second));
    final layout = BlogLayoutService(root.path);
    await layout.activate('minimal');
    final config = await TemplateConfiguration.load(repo.store);
    expect(config.document['id'], 'minimal');
    expect(
      config.value(config.fields.firstWhere((f) => f['key'] == 'themeColor')),
      '#112233',
    );
    expect(
      (await repo.read(post.relativePath)).originalBytes,
      post.originalBytes,
    );
    await layout.activate('butterfly');
    final reopened = await TemplateConfiguration.load(repo.store);
    expect(
      reopened.value(
        reopened.fields.firstWhere((f) => f['key'] == 'themeColor'),
      ),
      '#AABBCC',
    );
    final package = File('${dest.path}/package.json');
    final doc = jsonDecode(await package.readAsString()) as Map;
    doc['dependencies']['vue'] = '^99.0.0';
    await package.writeAsString(jsonEncode(doc));
    await layout.activate('minimal');
    expect(await layout.activeTemplate(), 'minimal');
  });
  test('configuration autosave shares the flush barrier; About uses the same editor without becoming an article', () async {
    await ProjectService(installer: installer).initialize(root.path);
    final editor = WebMarkdownController();
    final session = EditorSession(editor: editor);
    try {
      expect(await session.openProject(root.path), true);
      final count = session.index.articles.length;
      session.updateConfiguration('announcement', '配置自动保存');
      expect(session.dirty, true);
      expect(
        await session.openAbout(),
        true,
      ); // flushes config before loading About
      expect(session.dirty, false);
      expect(session.article!.about, true);
      editor.protocol.markdown = '# 关于我\n\n**中文介绍**\n';
      editor.notifyListeners();
      expect(await session.flush(), true);
      expect(
        await File('${root.path}/resource/about.md').readAsString(),
        contains('**中文介绍**'),
      );
      expect(session.index.articles.length, count);
      await File('${root.path}/${session.configuration!.path}')
          .writeAsString('{}');
      session.updateConfiguration('announcement', '保留输入');
      expect(await session.closeArticle(), false);
      expect(session.status, SaveStatus.conflict);
      expect(
        session.configuration!.value(
          session.configuration!.fields.firstWhere(
            (f) => f['key'] == 'announcement',
          ),
        ),
        '保留输入',
      );
    } finally {
      session.dispose();
    }
  });
}
