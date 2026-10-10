import 'package:blog_studio/controllers/web_markdown_controller.dart';

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:blog_studio/storage/file_store.dart';
import 'package:blog_studio/services/blog_layout_service.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:blog_studio/services/template_installer.dart';
import 'package:blog_studio/services/project_service.dart';
import 'package:blog_studio/storage/blog_configuration.dart';
import 'package:blog_studio/storage/resource_layout.dart';
import 'package:blog_studio/ui/pages/general_configuration_page.dart';
import 'package:blog_studio/services/editor_session.dart';
import 'package:blog_studio/storage/article_repository.dart';
import 'package:blog_studio/storage/template_configuration.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final service = ProjectService(
    installer: TemplateInstaller(readAsset: (p) => File(p).readAsBytes()),
  );
  test('new blog has exactly three root entries and content remains external to theme', () async {
    final root = await Directory.systemTemp.createTemp('inkjian-v2-');
    try {
      await service.initialize(root.path);
      final names =
          (await root.list().toList())
              .map((f) => f.uri.pathSegments.where((s) => s.isNotEmpty).last)
              .toList()
            ..sort();
      expect(names, ['blog.json', 'resource', 'template']);
      final marker = jsonDecode(
        await File('${root.path}/blog.json').readAsString(),
      ) as Map;
      expect(marker['formatVersion'], 2);
      expect(marker['site']['title'], '拾笺 InkJian');
      final layout = ResourceLayout(root.path);
      expect(layout.packageRoot, '${root.path}/template/butterfly');
      expect(await File('${layout.packageRoot}/package.json').exists(), true);
      expect(await Directory('${layout.packageRoot}/source').exists(), false);
      final repo = ArticleRepository(root.path);
      final article = await repo.create('新文章');
      expect(article.relativePath, startsWith('resource/drafts/'));
      expect((await repo.createNote()).note, true);
      expect((await repo.openAbout()).about, true);
      expect((await repo.scan()).articles, isNotEmpty);
      expect(
        await Directory('${root.path}/resource/images').list().toList(),
        isEmpty,
      );
      expect(await Directory('${layout.packageRoot}/resource').exists(), false);
      // Optional fixture is the actual initializer output, used for JS preview verification.
      const fixture = String.fromEnvironment('INKJIAN_FIXTURE');
      if (fixture.isNotEmpty) {
        final dest = Directory(fixture);
        await dest.create(recursive: true);
        for (final entity in await root.list(recursive: true).toList()) {
          if (entity is! File) continue;
          final relative = entity.path.substring(root.path.length + 1);
          final file = File('${dest.path}/$relative');
          await file.parent.create(recursive: true);
          await entity.copy(file.path);
        }
        for (final name in ['posts', 'drafts', 'notes', 'images']) {
          await Directory('${dest.path}/resource/$name')
              .create(recursive: true);
        }
      }
    } finally {
      await root.delete(recursive: true);
    }
  });
  test('installing another theme keeps shared resources and isolates static images', () async {
    final root = await Directory.systemTemp.createTemp(
      'inkjian-style-install-',
    );
    try {
      await service.initialize(root.path);
      await File('${root.path}/resource/images/cover.svg')
          .writeAsString('user image');
      final original = await File('${root.path}/resource/images/cover.svg')
          .readAsBytes();
      final source = jsonDecode(
        await File('assets/generated/template-manifest.json').readAsString(),
      ) as Map;
      final first = (source['templates'] as List).first as Map;
      final bytes = <String, Uint8List>{};
      final records = <Map<String, dynamic>>[];
      for (final record in first['files']) {
        final path = record['path'] as String;
        var data = await File('template/butterfly/$path').readAsBytes();
        if (path == 'template.json') {
          final config = jsonDecode(utf8.decode(data)) as Map;
          config['id'] = 'alternate';
          config['name'] = '另一主题';
          data = Uint8List.fromList(utf8.encode(jsonEncode(config)));
        }
        if (path == 'src/assets/cover.svg') {
          data = Uint8List.fromList(
            utf8.encode(
              '<svg xmlns="http://www.w3.org/2000/svg"><title>another theme</title></svg>',
            ),
          );
        }
        bytes['template/alternate/$path'] = data;
        records.add({
          'path': path,
          'length': data.length,
          'hash': contentHash(data),
        });
      }
      bytes['assets/generated/template-manifest.json'] = Uint8List.fromList(
        utf8.encode(
          jsonEncode({
            'version': '2',
            'templates': [
              {'id': 'alternate', 'name': '另一主题', 'files': records},
            ],
          }),
        ),
      );
      final installer = TemplateInstaller(
        readAsset: (path) async => bytes[path]!,
      );
      await installer.installStyle(root.path, 'alternate');
      await BlogLayoutService(root.path).activate('alternate');
      final repo = ArticleRepository(root.path);
      final config = await TemplateConfiguration.load(repo.store);
      expect(
        config.value(
          config.fields.firstWhere((f) => f['key'] == 'backgroundImage'),
        ),
        '',
      );
      expect(
        await File('${root.path}/resource/images/cover.svg').readAsBytes(),
        original,
      );
      expect(
        await File(
          '${root.path}/template/alternate/src/assets/cover.svg',
        ).readAsString(),
        contains('another theme'),
      );
      expect(
        (await BlogConfiguration.load(repo.store)).value('title'),
        '拾笺 InkJian',
      );
      expect(config.document.containsKey('site'), false);
    } finally {
      await root.delete(recursive: true);
    }
  });
  test('general config autosaves without changing theme config and detects external edits', () async {
    final root = await Directory.systemTemp.createTemp('inkjian-general-');
    final session = EditorSession(editor: WebMarkdownController());
    try {
      await service.initialize(root.path);
      expect(await session.openProject(root.path), true);
      final themeFile = File('${root.path}/${session.configuration!.path}');
      final themeBytes = await themeFile.readAsBytes();
      session.updateGeneralConfiguration('title', '我的日常');
      session.updateGeneralConfiguration('author', '小拾');
      expect(await session.openAbout(), true);
      expect(session.generalDirty, false);
      final marker = jsonDecode(
        await File('${root.path}/blog.json').readAsString(),
      ) as Map;
      expect(marker['site']['title'], '我的日常');
      expect(marker['activeTemplate'], 'butterfly');
      expect(await themeFile.readAsBytes(), themeBytes);
      final config = await BlogConfiguration.load(session.repository!.store);
      final disk = File('${root.path}/blog.json');
      await disk.writeAsString('${await disk.readAsString()}\n');
      await expectLater(
        config.change('title', '不覆盖').save(session.repository!.store),
        throwsException,
      );
      expect(await disk.readAsString(), isNot(contains('不覆盖')));
      expect(
        (await TemplateConfiguration.load(session.repository!.store)).document
            .containsKey('site'),
        false,
      );
    } finally {
      session.dispose();
      await root.delete(recursive: true);
    }
  });
  testWidgets(
    'general form saves text without rebuilding the input or losing selection',
    (tester) async {
      final root = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('inkjian-general-ui-'),
      ))!;
      final session = EditorSession(editor: WebMarkdownController());
      try {
        await tester.runAsync(() => service.initialize(root.path));
        await tester.runAsync(() => session.openProject(root.path));
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ListenableBuilder(
                listenable: session,
                builder: (_, _) => GeneralConfigurationPage(session: session),
              ),
            ),
          ),
        );
        final field = find.byType(TextFormField).first;
        await tester.enterText(field, '中文博客名称');
        await tester.pump();
        expect(session.generalConfiguration!.value('title'), '中文博客名称');
        expect(
          tester
              .widget<TextField>(
                find.descendant(of: field, matching: find.byType(TextField)),
              )
              .controller!
              .text,
          '中文博客名称',
        );
        await tester.runAsync(() => session.flush());
        await tester.pump();
        expect(find.text('中文博客名称'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      } finally {
        session.dispose();
        await tester.runAsync(() => root.delete(recursive: true));
      }
    },
  );
}
