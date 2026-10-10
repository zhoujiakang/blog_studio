import 'dart:io';

import 'package:blog_studio/models/project.dart';
import 'package:blog_studio/models/runtime_environment.dart';
import 'package:blog_studio/services/runtime_detector.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fixtures.dart';

Future<String> executable(
  Directory root,
  String name,
  String script, {
  bool allowExecute = true,
}) async {
  final file = File('${root.path}/$name');
  await file.writeAsString('#!/bin/sh\n$script\n');
  await Process.run('/bin/chmod', [allowExecute ? '700' : '600', file.path]);
  return file.path;
}

void main() {
  test('empty PATH reports missing without installing or writing', () async {
    final root = await temporaryProject();
    final detector = RuntimeDetector(
      environment: const {'PATH': ''},
      commonPaths: const [],
    );
    final result = await detector.detect(ProjectSession(root: root.path));
    expect(result.status, RuntimeStatus.missing);
    expect(await Directory('${root.path}/node_modules').exists(), false);
  });
  test(
    'common paths discover actual executables with isolated process PATH',
    () async {
      final root = await temporaryProject();
      await File('${root.path}/template/butterfly/package.json')
          .writeAsString('{"engines":{"node":">=22.18.0"}}');
      await executable(root, 'node', 'echo v22.21.1');
      await executable(root, 'npm', 'echo 10.9.4');
      final detector = RuntimeDetector(
        environment: const {'PATH': ''},
        commonPaths: [root.path],
      );
      final result = await detector.detect(ProjectSession(root: root.path));
      expect(result.status, RuntimeStatus.ready);
      expect(
        result.nodePath,
        await File('${root.path}/node').resolveSymbolicLinks(),
      );
      expect(
        detector.subprocessEnvironment(result.nodePath!)['PATH'],
        startsWith(await root.resolveSymbolicLinks()),
      );
    },
  );
  test(
    'Finder PATH discovers nvm and skips incompatible installed versions',
    () async {
      final root = await temporaryProject();
      await File('${root.path}/template/butterfly/package.json')
          .writeAsString('{"engines":{"node":">=22.18.0 <23.0.0"}}');
      for (final version in ['24.1.0', '22.21.1', '22.9.0']) {
        final bin = Directory('${root.path}/.nvm/versions/node/v$version/bin');
        await bin.create(recursive: true);
        await executable(bin, 'node', 'echo v$version');
        // npm needs the selected Node on PATH, as it does in a real install.
        await executable(bin, 'npm', 'node --version >/dev/null; echo 10.9.4');
      }
      final detector = RuntimeDetector(
        environment: {'HOME': root.path, 'PATH': '/usr/bin:/bin'},
        commonPaths: const [],
      );
      final result = await detector.detect(ProjectSession(root: root.path));
      expect(result.status, RuntimeStatus.ready);
      expect(result.nodeVersion, 'v22.21.1');
      expect(result.nodePath, contains('/v22.21.1/bin/node'));
    },
  );
  test('custom NVM_DIR works without shell startup files', () async {
    final root = await temporaryProject();
    await File('${root.path}/template/butterfly/package.json')
        .writeAsString('{"engines":{"node":">=22.18.0"}}');
    final bin = Directory('${root.path}/custom-nvm/versions/node/v22.21.1/bin');
    await bin.create(recursive: true);
    await executable(bin, 'node', 'echo v22.21.1');
    await executable(bin, 'npm', 'echo 10.9.4');
    final result = await RuntimeDetector(
      environment: {'NVM_DIR': '${root.path}/custom-nvm', 'PATH': ''},
      commonPaths: const [],
    ).detect(ProjectSession(root: root.path));
    expect(result.status, RuntimeStatus.ready);
    expect(result.nodePath, contains('/custom-nvm/'));
  });
  test(
    'old version, permission failure and timeout are distinguished',
    () async {
      final root = await temporaryProject();
      await File('${root.path}/template/butterfly/package.json')
          .writeAsString('{"engines":{"node":">=22.18.0"}}');
      await executable(root, 'node', 'echo v18.20.0');
      await executable(root, 'npm', 'echo 10.9.4');
      final detector = RuntimeDetector(
        environment: const {'PATH': ''},
        commonPaths: [root.path],
        timeout: const Duration(seconds: 1),
      );
      expect(
        (await detector.detect(ProjectSession(root: root.path))).status,
        RuntimeStatus.incompatible,
      );
      await executable(root, 'node', 'echo v22.21.1', allowExecute: false);
      expect(
        (await detector.detect(ProjectSession(root: root.path))).status,
        RuntimeStatus.inaccessible,
      );
      await executable(root, 'node', 'exec /bin/sleep 5');
      expect(
        (await detector.detect(ProjectSession(root: root.path))).reason,
        contains('超时'),
      );
    },
  );
}
