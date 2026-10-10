import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:blog_studio/services/managed_runtime.dart';
import 'package:blog_studio/services/runtime_detector.dart';
import 'package:blog_studio/models/project.dart';
import 'package:blog_studio/models/runtime_environment.dart';

void main() {
  test('release selection respects architecture and engine, prefers compatible LTS and rejects unsupported versions', () {
    final releases = [
      {
        'version': 'v26.0.0',
        'lts': false,
        'files': ['osx-arm64-tar'],
      },
      {
        'version': 'v24.18.0',
        'lts': 'Krypton',
        'files': ['osx-arm64-tar'],
      },
      {
        'version': 'v22.18.0',
        'lts': 'Jod',
        'files': ['osx-arm64-tar', 'osx-x64-tar'],
      },
      {
        'version': 'v22.23.0',
        'lts': 'Jod',
        'files': ['osx-arm64-tar', 'osx-x64-tar'],
      },
    ];
    expect(
      ManagedRuntime.selectRelease(releases, '>=22.18.0', 'arm64'),
      'v22.23.0',
    );
    expect(
      ManagedRuntime.selectRelease(releases, '>=24.0.0', 'arm64'),
      'v24.18.0',
    );
    expect(
      () => ManagedRuntime.selectRelease(releases, '>=24.0.0', 'x64'),
      throwsFormatException,
    );
    expect(
      () => ManagedRuntime.selectRelease(releases, '>=99.0.0', 'arm64'),
      throwsFormatException,
    );
    expect(
      () => ManagedRuntime.validateArchive(
        'node-v22.23.0-darwin-arm64/../../escape\n',
        'node-v22.23.0-darwin-arm64',
      ),
      throwsFormatException,
    );
    expect(
      () => ManagedRuntime.validateArchive(
        '/tmp/escape\n',
        'node-v22.23.0-darwin-arm64',
      ),
      throwsFormatException,
    );
  });
  test('verified portable runtime installs privately, can be reused and bad downloads/cancellation leave no partial installation', () async {
    final temp = await Directory.systemTemp.createTemp(
      'studio-managed-runtime-test-',
    );
    try {
      final project = Directory('${temp.path}/blog');
      await Directory('${project.path}/template/butterfly')
          .create(recursive: true);
      await File('${project.path}/blog.json')
          .writeAsString('{"formatVersion":2,"activeTemplate":"butterfly"}');
      await File('${project.path}/template/butterfly/package.json')
          .writeAsString('{"engines":{"node":">=22.18.0"}}');
      const folder = 'node-v22.23.0-darwin-arm64';
      final pack = Directory('${temp.path}/pack/$folder');
      await Directory('${pack.path}/bin').create(recursive: true);
      final node = File('${pack.path}/bin/node');
      await node.writeAsString('#!/bin/sh\necho v22.23.0\n');
      final npm = File('${pack.path}/bin/npm');
      await npm.writeAsString('#!/bin/sh\necho 10.9.4\n');
      await Process.run('/bin/chmod', ['700', node.path, npm.path]);
      final archive = File('${temp.path}/runtime.tar.gz');
      expect(
        (await Process.run('/usr/bin/tar', [
          '-czf',
          archive.path,
          '-C',
          '${temp.path}/pack',
          folder,
        ])).exitCode,
        0,
      );
      final bytes = await archive.readAsBytes();
      var broken = false, cancel = false, downloads = 0;
      late ManagedRuntime managed;
      Future<void> fetch(
        Uri uri,
        File target,
        int limit,
        void Function(int, int?) progress,
      ) async {
        expect(uri.host, 'nodejs.org');
        if (uri.path.endsWith('index.json')) {
          await target.writeAsString(
            jsonEncode([
              {
                'version': 'v22.23.0',
                'lts': 'Jod',
                'files': ['osx-arm64-tar'],
              },
            ]),
          );
        } else if (uri.path.endsWith('SHASUMS256.txt')) {
          await target.writeAsString(
            '${sha256.convert(bytes)}  $folder.tar.gz\n',
          );
        } else {
          downloads++;
          await target.writeAsBytes(broken ? [1, 2, 3] : bytes);
          progress(bytes.length, bytes.length);
          if (cancel) managed.cancel();
        }
      }

      final storage = Directory('${temp.path}/private-support');
      managed = ManagedRuntime(
        directory: storage,
        architecture: () async => 'arm64',
        fetcher: fetch,
      );
      final detector = RuntimeDetector(
        environment: const {'PATH': '/usr/bin:/bin'},
        commonPaths: const [],
      );
      final session = ProjectSession(root: project.path);
      final messages = <String>[];
      final installed = await managed.install(
        session,
        detector,
        (message, _) => messages.add(message),
      );
      expect(installed.status, RuntimeStatus.ready);
      expect(installed.nodePath, startsWith(storage.path));
      expect(await Directory('${project.path}/node_modules').exists(), false);
      expect(await managed.detect(session, detector), isNotNull);
      expect(downloads, 1);
      expect(messages.any((s) => s.contains('下载')), true);
      final before = (await storage.list().toList()).length;
      broken = true;
      await expectLater(
        managed.install(session, detector, (_, _) {}),
        throwsFormatException,
      );
      expect((await storage.list().toList()).length, before);
      broken = false;
      cancel = true;
      await expectLater(
        managed.install(session, detector, (_, _) {}),
        throwsA(isA<PreviewPreparationCancelled>()),
      );
      expect((await storage.list().toList()).length, before);
      expect(
        (await managed.detect(session, detector))!.status,
        RuntimeStatus.ready,
      );
    } finally {
      await temp.delete(recursive: true);
    }
  });
}
