import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:blog_studio/storage/file_store.dart';
import 'package:blog_studio/storage/path_guard.dart';
import 'package:blog_studio/services/template_service.dart';
import 'package:blog_studio/services/github_template_source.dart';
import 'package:blog_studio/services/template_installer.dart';

void main() {
  final files = <String, Uint8List>{};
  final manifest = jsonDecode(
    File('assets/generated/template-manifest.json').readAsStringSync(),
  ) as Map;
  for (final file in manifest['templates'][0]['files']) {
    files['template/butterfly/${file['path']}'] = File(
      'template/butterfly/${file['path']}',
    ).readAsBytesSync();
  }
  final manifestBytes = Uint8List.fromList(utf8.encode(jsonEncode(manifest)));
  test('downloads only raw main files without API or authentication and initializes v2', () async {
    final calls = <Uri>[];
    final source = GitHubTemplateSource(
      download: (uri, limit) async {
        calls.add(uri);
        expect(uri.host, 'raw.githubusercontent.com');
        expect(uri.path, contains('/main/'));
        final path = uri.path.split('/main/').last;
        return path == GitHubTemplateSource.manifestPath
            ? manifestBytes
            : files[path]!;
      },
    );
    final root = await Directory.systemTemp.createTemp('inkjian-github-test-');
    try {
      final installer = TemplateInstaller(source: source);
      expect(
        (await installer.listTemplates()).map((t) => t.id),
        contains('butterfly'),
      );
      await installer.initialize(root.path, templateId: 'butterfly');
      expect(
        await File('${root.path}/template/butterfly/src/App.vue').readAsBytes(),
        files['template/butterfly/src/App.vue'],
      );
      final blog = jsonDecode(
        await File('${root.path}/blog.json').readAsString(),
      );
      expect(blog['formatVersion'], 2);
      expect(await File('${root.path}/resource/about.md').exists(), true);
      expect(calls.every((u) => u.host == 'raw.githubusercontent.com'), true);
      expect(calls.length, files.length + 1);
      await source.prepare('butterfly');
      expect(calls.length, files.length + 1); // Verified bytes are reused.
    } finally {
      await root.delete(recursive: true);
    }
  });

  test('corrupt download leaves directory empty and retry succeeds', () async {
    var corrupt = true;
    final source = GitHubTemplateSource(
      download: (uri, limit) async {
        final path = uri.path.split('/main/').last;
        if (path == GitHubTemplateSource.manifestPath) return manifestBytes;
        if (corrupt && path.endsWith('/src/App.vue')) return Uint8List(0);
        return files[path]!;
      },
    );
    final root = await Directory.systemTemp.createTemp(
      'inkjian-download-fail-',
    );
    try {
      final installer = TemplateInstaller(source: source);
      await expectLater(installer.initialize(root.path), throwsFormatException);
      expect(await root.list().toList(), isEmpty);
      corrupt = false;
      await installer.initialize(root.path);
      expect(await File('${root.path}/blog.json').exists(), true);
    } finally {
      await root.delete(recursive: true);
    }
  });

  test('a changed main refreshes the whole catalog and installs only the new matching selection', () async {
    final current = Map<String, Uint8List>.from(files);
    final updated = jsonDecode(jsonEncode(manifest)) as Map;
    final records = updated['templates'][0]['files'] as List;
    final body = Uint8List.fromList(
      utf8.encode('<template>updated template</template>'),
    );
    current['template/butterfly/src/App.vue'] = body;
    final changed =
        records.firstWhere((r) => r['path'] == 'src/App.vue') as Map;
    changed['length'] = body.length;
    changed['hash'] = contentHash(body);
    final added = Uint8List.fromList(utf8.encode('export const added = true;'));
    current['template/butterfly/src/added.ts'] = added;
    records.add({
      'path': 'src/added.ts',
      'length': added.length,
      'hash': contentHash(added),
    });
    var catalogs = 0;
    final catalogUrls = <Uri>[];
    final source = GitHubTemplateSource(
      download: (uri, limit) async {
        expect(uri.host, 'raw.githubusercontent.com');
        final path = uri.path.split('/main/').last;
        if (path == GitHubTemplateSource.manifestPath) {
          catalogUrls.add(uri);
          catalogs++;
          return catalogs == 1
              ? manifestBytes
              : Uint8List.fromList(utf8.encode(jsonEncode(updated)));
        }
        return current[path]!;
      },
    );
    final root = await Directory.systemTemp.createTemp(
      'inkjian-catalog-change-',
    );
    try {
      await TemplateInstaller(source: source).initialize(root.path);
      expect(catalogs, 2);
      expect(catalogUrls[0].query, isNot(catalogUrls[1].query));
      expect(
        await File('${root.path}/template/butterfly/src/App.vue').readAsBytes(),
        body,
      );
      expect(
        await File('${root.path}/template/butterfly/src/added.ts')
            .readAsBytes(),
        added,
      );
    } finally {
      await root.delete(recursive: true);
    }
  });

  test('network failure does not retry or leave partial content', () async {
    var requests = 0;
    final source = GitHubTemplateSource(
      download: (_, limit) async {
        requests++;
        throw const SocketException('offline');
      },
    );
    final root = await Directory.systemTemp.createTemp('inkjian-network-fail-');
    try {
      await expectLater(
        TemplateInstaller(source: source).initialize(root.path),
        throwsA(isA<SocketException>()),
      );
      expect(requests, 1);
      expect(await root.list().toList(), isEmpty);
    } finally {
      await root.delete(recursive: true);
    }
  });

  test('rejects traversal catalog before downloading files', () async {
    var downloads = 0;
    final source = GitHubTemplateSource(
      download: (uri, limit) async {
        downloads++;
        return Uint8List.fromList(
          utf8.encode(
            jsonEncode({
              'version': '2',
              'templates': [
                {
                  'id': 'butterfly',
                  'name': 'Butterfly',
                  'files': [
                    {
                      'path': '../outside',
                      'length': 0,
                      'hash': contentHash([]),
                    },
                  ],
                },
              ],
            }),
          ),
        );
      },
    );
    await expectLater(
      source.read(GitHubTemplateSource.manifestPath),
      throwsFormatException,
    );
    expect(downloads, 1);
  });

  test('installed themes remain available when GitHub is offline', () async {
    final root = await Directory.systemTemp.createTemp(
      'inkjian-offline-theme-',
    );
    try {
      await TemplateInstaller(readAsset: (path) => File(path).readAsBytes())
          .initialize(root.path);
      final service = TemplateService(
        installer: TemplateInstaller(
          source: GitHubTemplateSource(
            download: (_, limit) async =>
                throw const SocketException('offline'),
          ),
        ),
      );
      final available = await service.available(
        FileStore(PathGuard(root.path)),
      );
      expect(available.single.id, 'butterfly');
    } finally {
      await root.delete(recursive: true);
    }
  });
  test(
    'catalog excludes newer app requirements and unsupported protocols',
    () async {
      final doc = jsonDecode(jsonEncode(manifest)) as Map;
      final original = doc['templates'][0] as Map;
      doc['templates'] = [
        original,
        {...original, 'id': 'future', 'minAppVersion': '9.0.0'},
        {...original, 'id': 'unsupported-protocol', 'protocolVersion': 3},
      ];
      final source = GitHubTemplateSource(
        download: (uri, limit) async {
          expect(uri.host, 'raw.githubusercontent.com');
          expect(uri.path, contains('/main/'));
          return Uint8List.fromList(utf8.encode(jsonEncode(doc)));
        },
      );
      final installer = TemplateInstaller(source: source);
      expect((await installer.listTemplates()).map((t) => t.id), ['butterfly']);
      await expectLater(
        source.read('template/future/src/App.vue'),
        throwsFormatException,
      );
    },
  );
  test('catalog requires explicit current protocol and minimum application version', () async {
    for (final key in ['protocolVersion', 'minAppVersion']) {
      final doc = jsonDecode(jsonEncode(manifest)) as Map;
      (doc['templates'][0] as Map).remove(key);
      final source = GitHubTemplateSource(
        download: (_, _) async =>
            Uint8List.fromList(utf8.encode(jsonEncode(doc))),
      );
      await expectLater(
        source.read(GitHubTemplateSource.manifestPath),
        throwsFormatException,
      );
    }
  });
}
