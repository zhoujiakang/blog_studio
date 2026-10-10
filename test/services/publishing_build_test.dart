import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:flutter_test/flutter_test.dart';
import 'package:blog_studio/models/project.dart';
import 'package:blog_studio/models/publishing.dart';
import 'package:blog_studio/services/preview_manager.dart';
import 'package:blog_studio/services/publishing/blog_builder.dart';
import 'package:blog_studio/services/template_installer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'real Vue build uses isolated output and never exports private note images',
    () async {
      final source = Directory.current.path;
      final root = await Directory.systemTemp.createTemp(
        'inkjian-publish-build-test-',
      );
      final environment = PreviewManager();
      WebsiteArtifact? artifact;
      try {
        final installer = TemplateInstaller(
          readAsset: (asset) => File(p.join(source, asset)).readAsBytes(),
        );
        await installer.initialize(root.path, templateId: 'butterfly');
        await Link(p.join(root.path, 'template/butterfly/node_modules'))
            .create(p.join(source, 'template/butterfly/node_modules'));
        const image =
            '<svg xmlns="http://www.w3.org/2000/svg"><rect width="1" height="1"/></svg>';
        await File(p.join(root.path, 'resource/images/public.svg'))
            .writeAsString(image);
        await File(p.join(root.path, 'resource/images/uppercase.svg'))
            .writeAsString(image);
        await File(p.join(root.path, 'resource/posts/uppercase.MD'))
            .writeAsString(
              '---\ntitle: Uppercase\n---\n![uppercase](/img/uppercase.svg)',
            );
        await File(p.join(root.path, 'resource/images/private-note.svg'))
            .writeAsString(image);
        await File(
          p.join(root.path, 'resource/posts/public.md'),
        ).writeAsString('---\ntitle: Public\n---\n![public](/img/public.svg)');
        await File(p.join(root.path, 'resource/notes/private.md'))
            .writeAsString('PRIVATE_NOTE_CONTENT\n![](/img/private-note.svg)');
        artifact = await BlogBuilder(environment)
            .build(ProjectSession(root: root.path), progress: (_) {});
        expect(artifact.files, contains('index.html'));
        expect(
          artifact.files.values
              .map((bytes) => utf8.decode(bytes, allowMalformed: true))
              .join(),
          contains('data:image/svg+xml'),
        );
        expect(artifact.files, contains('img/public.svg'));
        expect(artifact.files, contains('img/uppercase.svg'));
        expect(artifact.files, isNot(contains('img/private-note.svg')));
        expect(
          artifact.files.values
              .map((bytes) => utf8.decode(bytes, allowMalformed: true))
              .join(),
          isNot(contains('PRIVATE_NOTE_CONTENT')),
        );
        expect(await Directory(p.join(root.path, 'dist')).exists(), false);
        expect(environment.url, isNull);
        await File(p.join(root.path, 'resource/posts/uppercase.MD'))
            .writeAsString(
              '---\ntitle: Changed uppercase\n---\nChanged externally',
            );
        await expectLater(
          artifact.verifyUnchanged(),
          throwsA(isA<PublishingException>()),
        );
      } finally {
        await artifact?.dispose();
        await environment.shutdown();
        environment.dispose();
        await root.delete(recursive: true);
      }
    },
    skip: Platform.environment['INKJIAN_TEST_BUILD'] != '1',
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
