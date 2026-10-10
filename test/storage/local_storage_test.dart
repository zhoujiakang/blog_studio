import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:blog_studio/storage/path_guard.dart';
import 'package:blog_studio/storage/front_matter_codec.dart';
import 'package:blog_studio/storage/file_store.dart';
import 'package:blog_studio/services/template_installer.dart';
import 'package:blog_studio/services/project_service.dart';
import 'package:blog_studio/storage/article_repository.dart';
import 'package:blog_studio/storage/trash_repository.dart';
import 'package:blog_studio/models/project.dart';

void main() {
  late Directory root;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('studio-storage-test-');
  });
  tearDown(() async {
    await root.delete(recursive: true);
  });
  test(
    'guard rejects traversal and symlink parents without touching outside',
    () async {
      final guard = PathGuard(root.path);
      expect(() => guard.resolve('../escape.md'), throwsA(isA<Exception>()));
      final outside = await Directory.systemTemp.createTemp('studio-outside-');
      try {
        await Link('${root.path}/resource').create(outside.path);
        expect(
          () => guard.resolve('resource/posts/a.md'),
          throwsA(isA<Exception>()),
        );
        expect(await outside.list().toList(), isEmpty);
      } finally {
        await outside.delete();
      }
    },
  );
  test('front matter preserves CRLF, unknown nested values, comments and body', () {
    const source =
        '---\r\n# note\r\ntitle: "旧标题"\r\ntags:\r\n  - one\r\n  - two\r\ncustom:\r\n  enabled: true # keep\r\ndate: 2026-10-08 10:00:00\r\n---\r\n\r\n正文\r\n';
    final doc = FrontMatterDocument.parse(source);
    expect(doc.encode(doc.body, {}), source);
    final changed = doc.encode(doc.body, {
      'title': '新标题',
      'tags': ['中文'],
    });
    expect(changed, contains('custom:\r\n  enabled: true # keep\r\n'));
    expect(changed, contains('# note\r\n'));
    expect(FrontMatterDocument.parse(changed).body, doc.body);
    expect(FrontMatterDocument.parse(changed).fields['tags'], ['中文']);
    expect(
      () => FrontMatterDocument.parse('---\ntitle: bad\n'),
      throwsA(isA<Exception>()),
    );
  });
  test(
    'file conflicts preserve external data and latest original backup',
    () async {
      final store = FileStore(PathGuard(root.path));
      final hash = await store.write(
        'resource/drafts/a.md',
        utf8.encode('original'),
        expectedHash: null,
      );
      await File('${root.path}/resource/drafts/a.md').writeAsString('external');
      expect(
        () => store.write(
          'resource/drafts/a.md',
          utf8.encode('mine'),
          expectedHash: hash,
        ),
        throwsA(isA<Exception>()),
      );
      expect(utf8.decode(await store.read('resource/drafts/a.md')), 'external');
      await store.write(
        'resource/drafts/a.md',
        utf8.encode('next'),
        expectedHash: contentHash(utf8.encode('external')),
      );
      expect(
        utf8.decode(
          await store.read('.blog-studio/backups/resource/drafts/a.md'),
        ),
        'external',
      );
    },
  );
  test(
    'bundled template initializes and refuses nonempty directories',
    () async {
      final installer = TemplateInstaller(
        readAsset: (asset) async =>
            Uint8List.fromList(await File(asset).readAsBytes()),
      );
      final service = ProjectService(installer: installer);
      expect((await service.inspect(root.path)).kind, DirectoryKind.empty);
      final project = await service.initialize(root.path);
      expect((await service.inspect(root.path)).kind, DirectoryKind.compatible);
      final before = await File('${project.root}/blog.json').readAsBytes();
      expect(() => service.initialize(root.path), throwsA(isA<Exception>()));
      await service.open(root.path);
      expect(await File('${project.root}/blog.json').readAsBytes(), before);
      expect(await Directory('${root.path}/node_modules').exists(), false);
    },
  );
  test(
    'article flow: search, metadata, publish, recover, collision and reopen',
    () async {
      final repo = ArticleRepository(root.path);
      var article = await repo.create('测试文章');
      expect(article.draft, true);
      article = await repo.save(
        article,
        '# 标题\n\n搜得到的正文\n\n![图](/img/example.png)\n',
        {
          'tags': ['Dart', 'Dart'],
          'custom': {'value': 7},
        },
      );
      final index = await repo.scan();
      expect(index.tags, ['Dart']);
      expect(index.articles.single.searchText, contains('搜得到'));
      article = await repo.setDraft(article, false);
      expect(article.draft, false);
      final reopened = await repo.read(article.relativePath);
      expect(reopened.bodySource, article.bodySource);
      expect(reopened.frontMatter['custom']['value'], 7);
      final trash = TrashRepository(repo.store);
      await trash.remove(article);
      expect((await repo.scan()).articles, isEmpty);
      final entry = (await trash.list()).single;
      await repo.store.write(
        entry.originalPath,
        utf8.encode('conflict'),
        expectedHash: null,
      );
      expect(() => trash.restore(entry), throwsA(isA<Exception>()));
      expect((await trash.list()).length, 1);
      await File('${root.path}/${entry.originalPath}').delete();
      await trash.restore(entry);
      expect(
        (await repo.read(article.relativePath)).originalBytes,
        article.originalBytes,
      );
      expect(await trash.list(), isEmpty);
    },
  );
  test(
    'current article attributes reject scalar lists and string booleans',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'studio-current-attributes-',
      );
      try {
        final repo = ArticleRepository(root.path);
        await Directory('${root.path}/resource/posts').create(recursive: true);
        for (final field in [
          'tags: Vue',
          'categories: [[技术, 前端]]',
          'draft: "true"',
          'published: "false"',
        ]) {
          await File('${root.path}/resource/posts/invalid.md')
              .writeAsString('---\n$field\n---\nbody');
          await expectLater(
            repo.read('resource/posts/invalid.md'),
            throwsFormatException,
          );
          expect(
            (await repo.scan()).errors,
            contains('resource/posts/invalid.md'),
          );
        }
        final post = await repo.create('当前格式');
        await expectLater(
          repo.save(post, 'body', {'tags': 'Vue'}),
          throwsFormatException,
        );
        final saved = await repo.save(post, 'body', {
          'tags': ['Vue'],
          'categories': ['技术/Flutter'],
        });
        expect(saved.frontMatter['categories'], ['技术/Flutter']);
      } finally {
        await root.delete(recursive: true);
      }
    },
  );
}
