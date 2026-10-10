import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:blog_studio/models/blog_template.dart';
import 'package:blog_studio/services/template_installer.dart';
import 'package:blog_studio/storage/file_store.dart';
import 'package:blog_studio/ui/dialogs/template_picker_dialog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'generator discovers styles without registering template assets',
    () async {
      final fixture = await Directory.systemTemp.createTemp(
        'studio-catalog-test-',
      );
      final script = File('tool/generate_template_manifest.dart').absolute.path;
      final packages = File('.dart_tool/package_config.json').absolute.path;
      try {
        for (final id in ['butterfly', '简约']) {
          final style = '${fixture.path}/template/$id';
          await Directory(style).create(recursive: true);
          await Directory('$style/src').create();
          for (final path in ['package.json', 'src/App.vue', '.gitignore']) {
            await File('$style/$path').writeAsString(id);
          }
          await File('$style/template.json').writeAsString(
            jsonEncode({
              'formatVersion': 1,
              'id': id,
              'name': id,
              'fields': [],
              'minAppVersion': '1.1.2',
            }),
          );
          await Directory('$style/node_modules').create();
          await File('$style/node_modules/ignored.js')
              .writeAsString('excluded');
        }
        final pubspec = File('${fixture.path}/pubspec.yaml');
        await pubspec.writeAsString(
          'flutter:\n  assets:\n    - assets/editor/\n',
        );
        for (var run = 0; run < 2; run++) {
          final result = await Process.run('dart', [
            '--packages=$packages',
            script,
          ], workingDirectory: fixture.path);
          expect(result.exitCode, 0, reason: '${result.stderr}');
        }
        final manifest = jsonDecode(
          await File('${fixture.path}/assets/generated/template-manifest.json')
              .readAsString(),
        ) as Map;
        final templates = manifest['templates'] as List;
        expect(templates.map((t) => t['id']), ['butterfly', '简约']);
        expect(
          (templates[1]['files'] as List).map((f) => f['path']),
          contains('.gitignore'),
        );
        expect(
          (templates[1]['files'] as List).map((f) => f['path']),
          isNot(contains('node_modules/ignored.js')),
        );
        final yaml = await pubspec.readAsString();
        expect(yaml, 'flutter:\n  assets:\n    - assets/editor/\n');
        await Directory('${fixture.path}/template/butterfly/resource/posts')
            .create(recursive: true);
        final rejected = await Process.run('dart', [
          '--packages=$packages',
          script,
        ], workingDirectory: fixture.path);
        expect(rejected.exitCode, isNot(0));
        expect(rejected.stderr, contains('不应包含 resource/'));
      } finally {
        await fixture.delete(recursive: true);
      }
    },
  );
  test('catalog rejects user content, dependencies and build output before installation', () async {
    final source = jsonDecode(
      await File('assets/generated/template-manifest.json').readAsString(),
    ) as Map;
    for (final path in [
      'resource/posts/private.md',
      'node_modules/module.js',
      'dist/index.html',
    ]) {
      final manifest = jsonDecode(jsonEncode(source)) as Map;
      (manifest['templates'][0]['files'] as List).add({
        'path': path,
        'length': 0,
        'hash': contentHash([]),
      });
      final root = await Directory.systemTemp.createTemp(
        'inkjian-invalid-theme-',
      );
      try {
        final installer = TemplateInstaller(
          readAsset: (asset) async =>
              asset == 'assets/generated/template-manifest.json'
              ? Uint8List.fromList(utf8.encode(jsonEncode(manifest)))
              : await File(asset).readAsBytes(),
        );
        await expectLater(
          installer.initialize(root.path),
          throwsFormatException,
        );
        expect(await root.list().toList(), isEmpty);
      } finally {
        await root.delete(recursive: true);
      }
    }
  });
  test('selected style initializes only the current blog layout', () async {
    final root = await Directory.systemTemp.createTemp('studio-style-test-');
    final assets = <String, Uint8List>{};
    final templates = <Map<String, Object>>[];
    for (final id in ['butterfly', 'minimal']) {
      final bytes = Uint8List.fromList(
        utf8.encode(
          jsonEncode({'formatVersion': 1, 'id': id, 'name': id, 'fields': []}),
        ),
      );
      assets['template/$id/template.json'] = bytes;
      templates.add({
        'id': id,
        'name': id,
        'files': [
          {
            'path': 'template.json',
            'length': bytes.length,
            'hash': contentHash(bytes),
          },
        ],
      });
    }
    assets['assets/generated/template-manifest.json'] = Uint8List.fromList(
      utf8.encode(jsonEncode({'version': '2', 'templates': templates})),
    );
    final reads = <String>[];
    final installer = TemplateInstaller(
      readAsset: (path) async {
        reads.add(path);
        return assets[path]!;
      },
    );
    try {
      expect((await installer.listTemplates()).map((t) => t.id), [
        'butterfly',
        'minimal',
      ]);
      await expectLater(
        installer.initialize(root.path, templateId: '../escape'),
        throwsException,
      );
      expect(await root.list().toList(), isEmpty);
      // Integrity failure is detected before writing any target files.
      final good = assets['template/minimal/template.json']!;
      assets['template/minimal/template.json'] = Uint8List.fromList([0]);
      await expectLater(
        installer.initialize(root.path, templateId: 'minimal'),
        throwsException,
      );
      expect(await root.list().toList(), isEmpty);
      assets['template/minimal/template.json'] = good;
      await installer.initialize(root.path, templateId: 'minimal');
      expect(
        await File('${root.path}/template/minimal/template.json')
            .readAsString(),
        contains('minimal'),
      );
      expect(await Directory('${root.path}/minimal').exists(), false);
      expect(await Directory('${root.path}/butterfly').exists(), false);
      expect(reads, isNot(contains('template/butterfly/template.json')));
      await expectLater(
        installer.initialize(root.path, templateId: 'butterfly'),
        throwsException,
      );
      expect(
        await File('${root.path}/template/minimal/template.json')
            .readAsString(),
        contains('minimal'),
      );
    } finally {
      await root.delete(recursive: true);
    }
  });

  testWidgets(
    'picker confirms selected style and cancel returns no selection',
    (tester) async {
      const templates = [
        BlogTemplate(id: 'butterfly', name: 'butterfly', files: []),
        BlogTemplate(id: 'minimal', name: 'minimal', files: []),
      ];
      String? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              child: const Text('打开选择'),
              onPressed: () async {
                result = await showDialog<String>(
                  context: context,
                  builder: (_) => const TemplatePickerDialog(
                    root: '/tmp/empty-blog',
                    templates: templates,
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开选择'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('minimal'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('创建博客'));
      await tester.pumpAndSettle();
      expect(result, 'minimal');
      await tester.tap(find.text('打开选择'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(result, isNull);
      expect(tester.takeException(), isNull);
    },
  );
}
